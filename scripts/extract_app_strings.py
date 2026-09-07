#!/usr/bin/env python3
"""Extract every flat Persian AppStrings entry; map data is never included.

The Flutter source uses both single-quoted and double-quoted Dart string
literals. The extractor must therefore understand both forms, including
escaped characters and values split across lines. This file is the single
source-of-truth extractor used before locale generation.
"""

import argparse
import json
import re
from pathlib import Path


_SINGLE = re.compile(
    r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'",
    flags=re.S,
)
_DOUBLE = re.compile(
    r'"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"',
    flags=re.S,
)


def unescape(value: str) -> str:
    return (
        value.replace(r"\'", "'")
        .replace(r'\"', '"')
        .replace(r"\n", "\n")
        .replace(r"\r", "\r")
        .replace(r"\t", "\t")
        .replace(r"\\", "\\")
    )


def extract(source: str) -> dict[str, str]:
    marker = "'fa': {"
    start = source.index(marker) + len(marker)
    end = source.index("    'en': {", start)
    fa_block = source[start:end]

    values: dict[str, str] = {}
    for pattern in (_SINGLE, _DOUBLE):
        for match in pattern.finditer(fa_block):
            key = unescape(match.group(1))
            value = unescape(match.group(2))
            if key in values and values[key] != value:
                raise ValueError(f"Duplicate key with conflicting values: {key}")
            values[key] = value

    if len(values) < 100:
        raise ValueError(
            f"Expected a full AppStrings table; extracted only {len(values)} keys"
        )
    return dict(sorted(values.items()))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    values = extract(args.source.read_text(encoding="utf-8"))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(values, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Extracted {len(values)} non-map UI strings -> {args.out}")


if __name__ == "__main__":
    main()
