#!/usr/bin/env python3
"""Validate an interview-experience archive and its local Markdown image links."""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path
from urllib.parse import unquote


IMAGE_LINK = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")
SOURCE_URL = re.compile(r"^- 原帖链接：\s*https?://", re.MULTILINE)
PUBLISHED_AT = re.compile(r"^- 发布时间：\s*\S+", re.MULTILINE)
NOTE_ID = re.compile(r"^- note ID：\s*(\S+)", re.MULTILINE)
HTML_IMAGE_SRC = re.compile(r'<img\b[^>]*\bsrc=["\']([^"\']+)["\']', re.IGNORECASE)
HTML_POST_ANCHOR = re.compile(r'\bid=["\'](P\d{2})["\']', re.IGNORECASE)
HTML_SOURCE_REF = re.compile(r'\bhref=["\']#(P\d{2})["\']', re.IGNORECASE)
HTML_XHS_LINK = re.compile(r'\bhref=["\']https?://(?:www\.)?xiaohongshu\.com/[^"\']+["\']', re.IGNORECASE)
MARKDOWN_SOURCE_REF = re.compile(r'\[P(\d{2})\]')


def validate_markdown_links(markdown_file: Path) -> list[str]:
    errors: list[str] = []
    text = markdown_file.read_text(encoding="utf-8")
    for raw_link in IMAGE_LINK.findall(text):
        cleaned = raw_link.strip()
        if cleaned.startswith("<") and cleaned.endswith(">"):
            link = cleaned[1:-1]
        else:
            link = cleaned.split(" ", 1)[0]
        link = unquote(link)
        if link.startswith(("http://", "https://", "data:")):
            continue
        target = (markdown_file.parent / Path(link)).resolve()
        if not target.is_file():
            errors.append(f"Broken image link in {markdown_file}: {raw_link}")
    return errors


def validate(root: Path) -> dict[str, object]:
    errors: list[str] = []
    warnings: list[str] = []
    seen_note_ids: dict[str, Path] = {}

    for required in (
        root / "JD.md",
        root / "面经汇总.md",
        root / "面经汇总.docx",
        root / "面经汇总.html",
        root / "帖子",
    ):
        if not required.exists():
            errors.append(f"Missing required path: {required}")

    posts_root = root / "帖子"
    post_dirs = sorted(path for path in posts_root.iterdir() if path.is_dir()) if posts_root.is_dir() else []
    if not post_dirs:
        warnings.append("No post directories found.")

    for post_dir in post_dirs:
        post_file = post_dir / "帖子.md"
        metadata_file = post_dir / "metadata.json"
        images_dir = post_dir / "图片"
        if not post_file.is_file():
            errors.append(f"Missing 帖子.md: {post_dir}")
            continue
        text = post_file.read_text(encoding="utf-8")
        if not SOURCE_URL.search(text):
            errors.append(f"Missing source URL: {post_file}")
        if not PUBLISHED_AT.search(text):
            errors.append(f"Missing publication time: {post_file}")
        match = NOTE_ID.search(text)
        if not match:
            errors.append(f"Missing note ID: {post_file}")
        else:
            note_id = match.group(1)
            if note_id in seen_note_ids:
                errors.append(f"Duplicate note ID {note_id}: {seen_note_ids[note_id]} and {post_file}")
            seen_note_ids[note_id] = post_file
        if not metadata_file.is_file():
            warnings.append(f"Missing metadata.json: {post_dir}")
        if not images_dir.is_dir():
            errors.append(f"Missing image directory: {post_dir}")
        errors.extend(validate_markdown_links(post_file))

    summary = root / "面经汇总.md"
    if summary.is_file():
        errors.extend(validate_markdown_links(summary))
        markdown_image_count = len(IMAGE_LINK.findall(summary.read_text(encoding="utf-8")))

        html_summary = root / "面经汇总.html"
        if html_summary.is_file():
            html_text = html_summary.read_text(encoding="utf-8")
            html_sources = HTML_IMAGE_SRC.findall(html_text)
            html_image_count = len(html_sources)
            if html_image_count != markdown_image_count:
                errors.append(
                    f"HTML image count differs from Markdown: {html_image_count} != {markdown_image_count}"
                )
            if "<meta charset=" not in html_text.lower():
                errors.append("HTML summary does not declare a charset.")
            anchors = set(HTML_POST_ANCHOR.findall(html_text))
            html_refs = set(HTML_SOURCE_REF.findall(html_text))
            markdown_refs = {f"P{value}" for value in MARKDOWN_SOURCE_REF.findall(summary.read_text(encoding="utf-8"))}
            missing_targets = sorted(markdown_refs - anchors)
            missing_links = sorted(markdown_refs - html_refs)
            if missing_targets:
                errors.append(f"HTML is missing post anchors: {', '.join(missing_targets)}")
            if missing_links:
                errors.append(f"HTML citations are not linked: {', '.join(missing_links)}")
            if not HTML_XHS_LINK.search(html_text):
                errors.append("HTML does not contain clickable Xiaohongshu source links.")
            for src in html_sources:
                if src.startswith(("data:", "http://", "https://")):
                    if src.startswith(("http://", "https://")):
                        errors.append(f"HTML uses a remote image: {src}")
                    continue
                target = (html_summary.parent / Path(unquote(src))).resolve()
                if not target.is_file():
                    errors.append(f"Broken HTML image link: {src}")

        docx_summary = root / "面经汇总.docx"
        if docx_summary.is_file():
            try:
                with zipfile.ZipFile(docx_summary) as archive:
                    docx_image_count = sum(
                        1 for name in archive.namelist() if name.startswith("word/media/")
                    )
                if docx_image_count != markdown_image_count:
                    errors.append(
                        f"DOCX image count differs from Markdown: {docx_image_count} != {markdown_image_count}"
                    )
            except zipfile.BadZipFile:
                errors.append(f"Invalid DOCX package: {docx_summary}")

    return {
        "root": str(root),
        "posts": len(post_dirs),
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Task archive root")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.is_dir():
        print(f"Archive root does not exist: {root}", file=sys.stderr)
        return 2

    report = validate(root)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"Posts: {report['posts']}")
        for warning in report["warnings"]:
            print(f"WARNING: {warning}")
        for error in report["errors"]:
            print(f"ERROR: {error}")
        print("VALID" if report["valid"] else "INVALID")
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
