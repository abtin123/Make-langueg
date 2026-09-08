#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build every language pack in LANGUAGES straight from the already-translated
assets/local/<code>.json files and write out/lang_<code>.abl + out/manifest.json.

Unlike tool/l10n/translate_and_publish.py, this script never reads
lib/core/localization/app_localizations.dart — this repo (Make-langueg)
only carries the translated JSON, not the Flutter app source, so any step
that needs the .dart file cannot run here. This script is what CI uses to
turn the committed JSON into publishable packs.

Fails loudly (non-zero exit) if any language in LANGUAGES has no JSON file,
so a partial build can never silently get published.

Usage:
    python tool/l10n/build_release.py
"""

from __future__ import annotations

import gzip
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from langpack_config import LANGUAGES, NATIVE_NAMES, RTL  # noqa: E402

LOCAL = ROOT / "assets" / "local"
OUT = ROOT / "out"


def repo_base() -> str:
    env = os.environ.get("DOWNLOAD_BASE")
    if env:
        return env
    repo = os.environ.get("GITHUB_REPOSITORY", "abtin123/Make-langueg")
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    return f"{server}/{repo}/releases/download/langpacks-latest"


def main() -> None:
    fa_path = LOCAL / "fa.json"
    if not fa_path.exists():
        sys.exit(f"missing base locale: {fa_path}")
    fa = json.loads(fa_path.read_text(encoding="utf-8"))

    OUT.mkdir(exist_ok=True)
    base = repo_base()
    languages: list[dict] = []
    missing: list[str] = []

    for code in LANGUAGES:
        path = LOCAL / f"{code}.json"
        if not path.exists():
            missing.append(code)
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        raw = json.dumps(
            data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        packed = gzip.compress(raw, compresslevel=9, mtime=0)
        (OUT / f"lang_{code}.abl").write_bytes(packed)
        languages.append({
            "language_code": code,
            "language": NATIVE_NAMES.get(code, code),
            "direction": "rtl" if code in RTL else "ltr",
            "string_count": len(data),
            "size": len(packed),
            "sha256": hashlib.sha256(packed).hexdigest(),
            "version": hashlib.sha256(raw).hexdigest()[:16],
            "download_url": f"{base}/lang_{code}.abl",
        })

    if missing:
        sys.exit(
            f"aborting: {len(missing)} language file(s) missing from "
            f"assets/local/: {missing} — build must include all "
            f"{len(LANGUAGES)} languages."
        )

    manifest = {
        "schema_version": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "app_strings": "non-map-ui",
        "base_language": "fa",
        "string_count": len(fa),
        "languages": sorted(languages, key=lambda x: x["language_code"]),
    }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"built {len(languages)}/{len(LANGUAGES)} packs -> {OUT}")


if __name__ == "__main__":
    main()
