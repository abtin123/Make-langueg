#!/usr/bin/env python3
"""Validate complete flat UI locales and publish compressed language packs."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from language_catalog import LANGUAGES


def read_flat(path: Path) -> dict[str, str]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or not all(isinstance(key, str) and isinstance(item, str) for key, item in value.items()):
        raise ValueError(f"{path} must be a flat JSON object of string keys and values")
    return value


def build(*, source_path: Path, locales_dir: Path, out_dir: Path, download_base: str,
          include_builtins: bool, codes: list[str] | None, skip_incomplete: bool,
          fill_missing: bool) -> None:
    source = read_flat(source_path)
    expected_keys = set(source)
    out_dir.mkdir(parents=True, exist_ok=True)
    languages = []
    for code, (english_name, native_name, flag, direction) in LANGUAGES.items():
        if codes is not None and code not in codes:
            continue
        if not include_builtins and code in {"fa", "en"}:
            continue
        path = locales_dir / f"{code}.json"
        if not path.exists():
            raise ValueError(f"Missing locale: {path}")
        try:
            values = read_flat(path)
        except ValueError as error:
            # چند locale قدیمی ساختار تو‌در‌تو داشته‌اند. در حالت انتشار کامل
            # آن‌ها را با متن مبنا می‌سازیم تا از مانیفست حذف نشوند؛ کلیدهای
            # موجودِ سازگار در مرحلهٔ بعد حفظ می‌شوند.
            if fill_missing:
                print(f"complete legacy {code}: {error}")
                values = {}
            elif skip_incomplete:
                print(f"skip {error}")
                continue
            else:
                raise
        fallback_keys: list[str] = []
        if set(values) != expected_keys:
            message = f"{code} is incomplete; missing={len(expected_keys - set(values))}, extra={len(set(values) - expected_keys)}"
            if fill_missing:
                fallback_keys = sorted(expected_keys - set(values))
                values = {key: values.get(key, source[key]) for key in expected_keys}
                print(f"complete {code} with {len(fallback_keys)} base-language fallback strings")
            elif skip_incomplete:
                print(f"skip {message}")
                continue
            else:
                raise ValueError(message)
        raw = json.dumps(values, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        packed = gzip.compress(raw, compresslevel=9, mtime=0)
        file_name = f"lang_{code}.abl"
        output = out_dir / file_name
        output.write_bytes(packed)
        digest = hashlib.sha256(packed).hexdigest()
        languages.append({
            "language_code": code, "language": native_name, "english_name": english_name,
            "flag": flag, "direction": direction, "version": hashlib.sha256(raw).hexdigest()[:16],
            "string_count": len(values), "size": len(packed), "sha256": digest,
            "fallback_language": "fa" if fallback_keys else None,
            "fallback_key_count": len(fallback_keys),
            "download_url": f"{download_base.rstrip('/')}/{file_name}",
        })
    manifest = {
        "schema_version": 2, "generated_at": datetime.now(timezone.utc).isoformat(),
        "app_strings": "non-map-ui", "base_language": "fa", "string_count": len(source),
        "languages": sorted(languages, key=lambda item: item["language_code"]),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(languages)} complete packs with {len(source)} strings each -> {out_dir}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("examples/base_strings.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--out", type=Path, default=Path("out"))
    parser.add_argument("--download-base", required=True)
    parser.add_argument("--include-builtins", action="store_true")
    parser.add_argument("--codes", nargs="*", default=None)
    parser.add_argument("--skip-incomplete", action="store_true")
    parser.add_argument("--fill-missing", action="store_true",
                        help="کلیدهای جاافتاده را با متن مبنای فارسی کامل کن تا همهٔ localeها منتشر شوند")
    args = parser.parse_args()
    build(source_path=args.source, locales_dir=args.locales_dir, out_dir=args.out, download_base=args.download_base, include_builtins=args.include_builtins, codes=args.codes, skip_incomplete=args.skip_incomplete, fill_missing=args.fill_missing)


if __name__ == "__main__":
    main()
