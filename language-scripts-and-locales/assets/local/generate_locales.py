#!/usr/bin/env python3
"""Extract the app's key-based localization tables into assets/local/*.json.

Run from the project root:
    python assets/local/generate_locales.py

The source of truth is lib/core/localization/app_localizations.dart.
Existing translations are preserved; newly discovered keys are filled with
English so every locale has the same key set. Translation quality for newly
added keys should be reviewed before publishing language packs.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "lib/core/localization/app_localizations.dart"
OUT = ROOT / "assets/local"

LANGUAGES = [
    "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fr",
    "he", "hi", "hu", "id", "it", "ja", "ko", "nl", "no", "pl",
    "pt", "ro", "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

PAIR_PATTERNS = (
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", re.S),
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*\"((?:\\.|[^\"\\])*)\"", re.S),
    re.compile(r'"((?:\\.|[^"\\])*)"\s*:\s*\'((?:\\.|[^\'\\])*)\'', re.S),
    re.compile(r'"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"', re.S),
)


def unescape(value: str) -> str:
    return (
        value.replace(r"\\", "\\")
        .replace(r"\'", "'")
        .replace(r'\"', '"')
        .replace(r"\n", "\n")
        .replace(r"\r", "\r")
        .replace(r"\t", "\t")
    )


def extract_block(source: str, language: str) -> str:
    marker = f"    '{language}': {{"
    start = source.index(marker) + len(marker)
    if language == "fa":
        end = source.index("    'en': {", start)
    else:
        end = source.index("\n  };", start)
    return source[start:end]


def extract(source: str, language: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for pattern in PAIR_PATTERNS:
        for match in pattern.finditer(extract_block(source, language)):
            key, value = map(unescape, match.groups())
            if key in values and values[key] != value:
                raise ValueError(f"Conflicting duplicate key: {key}")
            values[key] = value
    return dict(sorted(values.items()))


def load_existing(code: str) -> dict[str, str]:
    path = OUT / f"{code}.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fa = extract(source, "fa")
    en = extract(source, "en")
    if len(fa) < 500 or set(fa) != set(en):
        raise SystemExit(
            f"Localization extraction failed: fa={len(fa)}, en={len(en)}"
        )

    OUT.mkdir(parents=True, exist_ok=True)
    for code in LANGUAGES:
        if code == "fa":
            data = fa
        elif code == "en":
            data = en
        else:
            old = load_existing(code)
            data = {key: old.get(key, en[key]) for key in fa}
        (OUT / f"{code}.json").write_text(
            json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    (OUT / "manifest.json").write_text(
        json.dumps(
            {
                "version": 1,
                "source": "lib/core/localization/app_localizations.dart",
                "key_count": len(fa),
                "languages": LANGUAGES,
                "fallback_language": "en",
            },
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(LANGUAGES)} locales × {len(fa)} keys in {OUT}")


if __name__ == "__main__":
    main()
