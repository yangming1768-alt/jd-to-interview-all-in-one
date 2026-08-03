#!/usr/bin/env python3
"""Run local PaddleOCR on a post's images and update the OCR section in 帖子.md."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
START_MARKER = "<!-- OCR:START -->"
END_MARKER = "<!-- OCR:END -->"


def natural_key(path: Path) -> list[Any]:
    return [int(part) if part.isdigit() else part.casefold() for part in re.split(r"(\d+)", path.name)]


def find_text_payload(value: Any) -> tuple[list[str], list[float]] | None:
    if isinstance(value, dict):
        if isinstance(value.get("rec_texts"), list):
            texts = [str(item).strip() for item in value["rec_texts"]]
            raw_scores = value.get("rec_scores", [])
            scores = [float(item) for item in raw_scores] if isinstance(raw_scores, (list, tuple)) else []
            return texts, scores
        for child in value.values():
            found = find_text_payload(child)
            if found:
                return found
    elif isinstance(value, (list, tuple)):
        for child in value:
            found = find_text_payload(child)
            if found:
                return found
    return None


def result_to_data(result: Any) -> Any:
    data = getattr(result, "json", None)
    if callable(data):
        data = data()
    if isinstance(data, str):
        return json.loads(data)
    if data is not None:
        return data
    if isinstance(result, dict):
        return result
    return {"repr": repr(result)}


def run_ocr(image_paths: list[Path]) -> list[dict[str, Any]]:
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        os.environ.setdefault(
            "PADDLE_PDX_CACHE_HOME",
            str(Path(local_app_data) / "RednoteInterviewSkill" / "models" / "paddleocr"),
        )
    try:
        from paddleocr import PaddleOCR
    except ImportError as exc:
        raise RuntimeError("PaddleOCR is not installed in the active Python environment.") from exc

    engine = PaddleOCR(
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        enable_mkldnn=False,
        text_detection_model_name="PP-OCRv5_mobile_det",
        text_recognition_model_name="PP-OCRv5_mobile_rec",
    )
    collected: list[dict[str, Any]] = []
    for image_path in image_paths:
        try:
            predictions = list(engine.predict(str(image_path)))
            lines: list[str] = []
            scores: list[float] = []
            for prediction in predictions:
                payload = find_text_payload(result_to_data(prediction))
                if not payload:
                    continue
                payload_lines, payload_scores = payload
                lines.extend(line for line in payload_lines if line)
                scores.extend(payload_scores)
            collected.append(
                {
                    "image": image_path.name,
                    "status": "ok" if lines else "unrecognized",
                    "text": "\n".join(lines) if lines else "[未能识别]",
                    "scores": scores,
                }
            )
        except Exception as exc:  # Preserve partial OCR output for the remaining images.
            collected.append(
                {
                    "image": image_path.name,
                    "status": "error",
                    "text": "[未能识别]",
                    "error": str(exc),
                    "scores": [],
                }
            )
    return collected


def build_markdown(results: list[dict[str, Any]], source_id: str, image_dir_name: str) -> str:
    blocks = [START_MARKER, "## 图片与 OCR", ""]
    for index, item in enumerate(results, start=1):
        image_id = f"{source_id}-I{index:02d}"
        relative_path = f"{image_dir_name}/{item['image']}"
        blocks.extend(
            [
                f"### {image_id}",
                "",
                f"![{image_id}]({relative_path})",
                "",
                str(item["text"]),
                "",
                "> OCR 由机器生成，可能存在识别错误，请以原图为准。",
                "",
            ]
        )
    blocks.append(END_MARKER)
    return "\n".join(blocks)


def update_post(post_file: Path, section: str) -> None:
    original = post_file.read_text(encoding="utf-8") if post_file.exists() else ""
    pattern = re.compile(re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER), re.DOTALL)
    if pattern.search(original):
        updated = pattern.sub(section, original, count=1)
    else:
        updated = original.rstrip() + "\n\n" + section + "\n"
    post_file.write_text(updated, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images_dir", type=Path, help="Directory containing a post's images")
    parser.add_argument("--post-file", type=Path, help="帖子.md to update")
    parser.add_argument("--source-id", help="Source identifier such as P01")
    parser.add_argument("--json-output", type=Path, help="OCR JSON output path")
    parser.add_argument("--dry-run", action="store_true", help="List images without loading PaddleOCR")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    images_dir = args.images_dir.resolve()
    if not images_dir.is_dir():
        print(f"Images directory does not exist: {images_dir}", file=sys.stderr)
        return 2

    image_paths = sorted(
        (path for path in images_dir.iterdir() if path.is_file() and path.suffix.casefold() in IMAGE_SUFFIXES),
        key=natural_key,
    )
    if not image_paths:
        print(f"No supported images found in: {images_dir}", file=sys.stderr)
        return 3

    if args.dry_run:
        print(json.dumps({"images": [path.name for path in image_paths]}, ensure_ascii=False, indent=2))
        return 0

    source_id = args.source_id or images_dir.parent.name.split("_", 1)[0]
    results = run_ocr(image_paths)
    json_output = args.json_output or images_dir.parent / "ocr-results.json"
    json_output.parent.mkdir(parents=True, exist_ok=True)
    json_output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    section = build_markdown(results, source_id, images_dir.name)
    if args.post_file:
        update_post(args.post_file, section)
    else:
        print(section)

    return 0 if all(item["status"] != "error" for item in results) else 4


if __name__ == "__main__":
    raise SystemExit(main())
