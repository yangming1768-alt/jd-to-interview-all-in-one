#!/usr/bin/env python3
"""Generate a local Chinese image and verify PaddleOCR can recognize it."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path


TEST_TEXT = "\u9762\u8bd5\u6d4b\u8bd5"


def find_font() -> Path:
    windows = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
    for name in ("msyh.ttc", "msyhbd.ttc", "simhei.ttf", "simsun.ttc"):
        candidate = windows / name
        if candidate.is_file():
            return candidate
    raise RuntimeError("No supported Windows Chinese font was found.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--models-dir", type=Path)
    args = parser.parse_args()

    if args.models_dir:
        args.models_dir.mkdir(parents=True, exist_ok=True)
        os.environ.setdefault("PADDLE_PDX_CACHE_HOME", str(args.models_dir.resolve()))

    from PIL import Image, ImageDraw, ImageFont
    from ocr_images import run_ocr

    with tempfile.TemporaryDirectory(prefix="rednote-ocr-") as temporary:
        image_path = Path(temporary) / "ocr-smoke.png"
        image = Image.new("RGB", (720, 180), "white")
        draw = ImageDraw.Draw(image)
        draw.text((40, 45), TEST_TEXT, fill="black", font=ImageFont.truetype(str(find_font()), 64))
        image.save(image_path)
        result = run_ocr([image_path])[0]

    recognized = str(result.get("text", ""))
    success = all(character in recognized for character in TEST_TEXT)
    report = {
        "success": success,
        "expected": TEST_TEXT,
        "recognized": recognized,
        "status": result.get("status"),
        "error": result.get("error"),
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    else:
        print(report)
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
