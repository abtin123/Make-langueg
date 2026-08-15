#!/usr/bin/env python3
"""
Build language packs from locales/*.json.

Usage:
    python scripts/build.py --locales-dir locales --out out

Output:
    out/<locale>.lpk   gzip-compressed JSON translation file
    out/manifest.json   manifest the app fetches first
"""
import argparse
import gzip
import hashlib
import json
import sys
from pathlib import Path


def flatten_keys(d, prefix=""):
    keys = set()
    for k, v in d.items():
        path = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            keys |= flatten_keys(v, path)
        else:
            keys.add(path)
    return keys


def build(locales_dir: Path, out_dir: Path, base_locale: str):
    out_dir.mkdir(parents=True, exist_ok=True)

    locale_files = sorted(locales_dir.glob("*.json"))
    if not locale_files:
        sys.exit(f"no locale files found in {locales_dir}")

    base_path = locales_dir / f"{base_locale}.json"
    base_keys = None
    if base_path.exists():
        base_keys = flatten_keys(json.loads(base_path.read_text(encoding="utf-8")))

    manifest = {"version": 1, "languages": {}}

    for path in locale_files:
        locale = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))

        if base_keys is not None:
            missing = base_keys - flatten_keys(data)
            if missing:
                print(f"warning: {locale} missing keys: {sorted(missing)}", file=sys.stderr)

        raw = json.dumps(data, ensure_ascii=False, sort_keys=True).encode("utf-8")
        version = hashlib.sha256(raw).hexdigest()[:12]
        packed = gzip.compress(raw, mtime=0)

        out_file = out_dir / f"{locale}.lpk"
        out_file.write_bytes(packed)

        manifest["languages"][locale] = {
            "file": out_file.name,
            "version": version,
            "size_bytes": len(packed),
            "sha256": hashlib.sha256(packed).hexdigest(),
        }
        print(f"{locale} -> {out_file} (v{version}, {len(packed)}B)")

    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"manifest -> {out_dir / 'manifest.json'}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--locales-dir", default="locales", type=Path)
    p.add_argument("--out", default="out", type=Path)
    p.add_argument("--base-locale", default="en")
    args = p.parse_args()
    build(args.locales_dir, args.out, args.base_locale)
