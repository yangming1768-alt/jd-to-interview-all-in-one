#!/usr/bin/env python3
"""Validate the optional personalized interview-answer deliverables."""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path


QUESTION_HEADING = re.compile(r"^#{2,4}\s+\[(Q\d{2,})\]", re.MULTILINE)
QUESTION_SOURCE = re.compile(r"\[(P\d{2})(?:-I\d{2})?\]")
PERSONAL_SOURCE = re.compile(r"\[(R\d{2}|M\d{2})\]")
STATUS = re.compile(r"材料判断[：:]\s*(可直接回答|部分信息|材料不足)")
HTML_ID = re.compile(r'\bid=["\'](Q\d{2,})["\']', re.IGNORECASE)
HTML_QUESTION_LINK = re.compile(r'\bhref=["\']#(Q\d{2,})["\']', re.IGNORECASE)
HTML_POST_LINK = re.compile(r'\bhref=["\'][^"\']*面经汇总\.html#(P\d{2})["\']', re.IGNORECASE)


def docx_text(path: Path) -> str:
    with zipfile.ZipFile(path) as archive:
        xml = archive.read("word/document.xml").decode("utf-8")
    return " ".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", xml, re.S))


def validate(root: Path) -> dict[str, object]:
    errors: list[str] = []
    warnings: list[str] = []
    required = [
        root / "个人材料索引.md",
        root / "面经回答.md",
        root / "面经回答.docx",
        root / "面经回答.html",
    ]
    for path in required:
        if not path.is_file():
            errors.append(f"Missing required answer file: {path}")

    answer_md = root / "面经回答.md"
    if not answer_md.is_file():
        return {"root": str(root), "valid": False, "questions": 0, "errors": errors, "warnings": warnings}

    md_text = answer_md.read_text(encoding="utf-8")
    matches = list(QUESTION_HEADING.finditer(md_text))
    question_ids = [match.group(1) for match in matches]
    if not question_ids:
        errors.append("No [Qxx] question headings found in 面经回答.md")
    if len(question_ids) != len(set(question_ids)):
        errors.append("Duplicate [Qxx] question IDs found in 面经回答.md")

    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(md_text)
        block = md_text[match.start():end]
        qid = match.group(1)
        if not QUESTION_SOURCE.search(block):
            errors.append(f"{qid} has no [Pxx] question source")
        if not STATUS.search(block):
            errors.append(f"{qid} has no valid material status")
        if "材料判断：可直接回答" in block and not PERSONAL_SOURCE.search(block):
            errors.append(f"{qid} is marked 可直接回答 but has no [Rxx]/[Mxx] evidence")

    if not PERSONAL_SOURCE.search(md_text):
        errors.append("No personal evidence citations [Rxx]/[Mxx] found")

    html_path = root / "面经回答.html"
    if html_path.is_file():
        html = html_path.read_text(encoding="utf-8")
        if "<meta charset=" not in html.lower():
            errors.append("面经回答.html does not declare a charset")
        ids = set(HTML_ID.findall(html))
        links = set(HTML_QUESTION_LINK.findall(html))
        expected = set(question_ids)
        if expected - ids:
            errors.append(f"HTML is missing question anchors: {', '.join(sorted(expected - ids))}")
        if expected - links:
            errors.append(f"HTML directory is missing question links: {', '.join(sorted(expected - links))}")
        post_refs = {match.group(1) for match in QUESTION_SOURCE.finditer(md_text)}
        linked_posts = set(HTML_POST_LINK.findall(html))
        if post_refs - linked_posts:
            errors.append(f"HTML is missing linked post citations: {', '.join(sorted(post_refs - linked_posts))}")

    docx_path = root / "面经回答.docx"
    if docx_path.is_file():
        try:
            text = docx_text(docx_path)
            missing = [qid for qid in question_ids if qid not in text]
            if missing:
                errors.append(f"DOCX is missing question IDs: {', '.join(missing)}")
        except (zipfile.BadZipFile, KeyError):
            errors.append(f"Invalid DOCX package: {docx_path}")

    return {
        "root": str(root),
        "valid": not errors,
        "questions": len(question_ids),
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
        print(f"Questions: {report['questions']}")
        for warning in report["warnings"]:
            print(f"WARNING: {warning}")
        for error in report["errors"]:
            print(f"ERROR: {error}")
        print("VALID" if report["valid"] else "INVALID")
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
