#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Validates the contract the AbtinMaps app relies on for downloadable
language packs:

  1. assets/local/<code>.json exists for every language in LANGUAGES,
     with exactly the same keys and the same {placeholder} tokens as
     assets/local/fa.json (the base language), and no empty values.

  2. With --require-complete: out/manifest.json lists every language,
     out/lang_<code>.abl exists for each one, is valid gzip, decodes to
     JSON identical to assets/local/<code>.json, and its sha256 matches
     the manifest entry. This is the check that used to be missing and
     made the "Build and Publish Language Packs" workflow fail before
     out/ was even built — run tool/l10n/build_release.py first.

Usage:
    python tests/validate_language_pack_contract.py
    python tests/validate_language_pack_contract.py --require-complete
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool" / "l10n"))
from langpack_config import LANGUAGES  # noqa: E402

LOCAL = ROOT / "assets" / "local"
OUT = ROOT / "out"
PLACEHOLDER = re.compile(r"\{[a-z_][a-z0-9_]*\}")


def fail(issues: list[str]) -> None:
    for it in issues:
        print(f"ISSUE {it}")
    sys.exit(f"contract failed: {len(issues)} issue(s)")


def check_locales() -> dict[str, dict[str, str]]:
    issues: list[str] = []
    fa_path = LOCAL / "fa.json"
    if not fa_path.exists():
        fail([f"missing base locale file: {fa_path}"])
    fa = json.loads(fa_path.read_text(encoding="utf-8"))
    locales: dict[str, dict[str, str]] = {"fa": fa}

    for code in LANGUAGES:
        path = LOCAL / f"{code}.json"
        if not path.exists():
            issues.append(f"{code}: assets/local/{code}.json is missing")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            issues.append(f"{code}: invalid JSON ({e})")
            continue
        locales[code] = data

        miss = set(fa) - set(data)
        extra = set(data) - set(fa)
        if miss:
            issues.append(f"{code}: missing {len(miss)} key(s), e.g. {sorted(miss)[:3]}")
        if extra:
            issues.append(f"{code}: {len(extra)} unexpected extra key(s)")

        empties = [k for k, v in data.items() if not str(v).strip()]
        if empties:
            issues.append(f"{code}: {len(empties)} empty value(s), e.g. {empties[:3]}")

        for k, v in fa.items():
            fph = set(PLACEHOLDER.findall(v))
            if fph and set(PLACEHOLDER.findall(data.get(k, ""))) != fph:
                issues.append(f"{code}: placeholder mismatch in '{k}'")

    if issues:
        fail(issues)
    print(f"locale parity OK: {len(LANGUAGES)} languages x {len(fa)} keys")
    return locales


def check_build(locales: dict[str, dict[str, str]]) -> None:
    issues: list[str] = []
    manifest_path = OUT / "manifest.json"
    if not manifest_path.exists():
        fail([f"{manifest_path} does not exist — run tool/l10n/build_release.py first"])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_code = {entry["language_code"]: entry for entry in manifest.get("languages", [])}

    for code in LANGUAGES:
        pack_path = OUT / f"lang_{code}.abl"
        if not pack_path.exists():
            issues.append(f"{code}: {pack_path.name} not built")
            continue
        raw = pack_path.read_bytes()
        try:
            payload = gzip.decompress(raw)
        except OSError as e:
            issues.append(f"{code}: {pack_path.name} is not valid gzip ({e})")
            continue

        entry = by_code.get(code)
        if entry is None:
            issues.append(f"{code}: not listed in manifest.json")
            continue
        if entry.get("sha256") != hashlib.sha256(raw).hexdigest():
            issues.append(f"{code}: manifest sha256 does not match {pack_path.name}")

        try:
            data = json.loads(payload.decode("utf-8"))
        except json.JSONDecodeError as e:
            issues.append(f"{code}: {pack_path.name} does not decode to JSON ({e})")
            continue
        if data != locales.get(code):
            issues.append(
                f"{code}: {pack_path.name} content does not match assets/local/{code}.json"
            )

    missing_from_manifest = sorted(set(LANGUAGES) - set(by_code))
    if missing_from_manifest:
        issues.append(f"manifest.json is missing: {missing_from_manifest}")

    if issues:
        fail(issues)
    print(f"build contract OK: {len(LANGUAGES)} packs built and match manifest.json")


def main() -> None:
    p = argparse.ArgumentParser(description="Validate the AbtinMaps language-pack contract")
    p.add_argument(
        "--require-complete",
        action="store_true",
        help="also verify out/lang_*.abl + out/manifest.json (post-build check)",
    )
    args = p.parse_args()
    locales = check_locales()
    if args.require_complete:
        check_build(locales)


if __name__ == "__main__":
    main()
