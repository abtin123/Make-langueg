#!/usr/bin/env python3
"""Extract every flat Persian AppStrings entry; map data is never included."""

import argparse
import json
import re
from pathlib import Path


def extract(source: str) -> dict[str, str]:
    marker = "'fa': {"
    start = source.index(marker) + len(marker)
    end = source.index("    'en': {", start)
    fa_block = source[start:end]
    pairs = re.findall(r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", fa_block, flags=re.S)
    def unescape(value: str) -> str:
        return value.replace(r"\'", "'").replace(r"\n", "\n").replace(r"\\", "\\")
    values = {unescape(key): unescape(value) for key, value in pairs}
    if len(values) < 100:
        raise ValueError(f"Expected a full AppStrings table; extracted only {len(values)} keys")
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    values = extract(args.source.read_text(encoding="utf-8"))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(values, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Extracted {len(values)} non-map UI strings -> {args.out}")


if __name__ == "__main__":
    main()
