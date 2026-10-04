#!/usr/bin/env python3
"""Merge the per-language build outputs into one release folder.

    python scripts/merge_release.py --packs packs --previous prev/manifest.json --out release

packs/<anything>/lang_xx.abl + manifest.json   (one folder per language job)
prev/manifest.json                              (manifest of the current release, optional)

Languages that were not rebuilt keep their old manifest entry (their old .abl
stays in the release because uploads use --clobber only for files we ship).
The sha256 of every shipped .abl is re-checked.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import shutil
import sys
from pathlib import Path


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--packs", type=Path, required=True)
    ap.add_argument("--previous", type=Path, default=None)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()

    langs: dict[str, dict] = {}
    if a.previous and a.previous.exists():
        for e in load(a.previous).get("languages", []):
            if isinstance(e, dict) and e.get("code"):
                langs[e["code"]] = e

    a.out.mkdir(parents=True, exist_ok=True)
    shipped, source_keys, engine = [], 0, ""
    for mf in sorted(a.packs.glob("*/manifest.json")):
        m = load(mf)
        source_keys = m.get("source_keys", source_keys)
        engine = m.get("engine", engine)
        for e in m.get("languages", []):
            f = mf.parent / f"lang_{e['code']}.abl"
            if not f.exists():
                continue
            raw = f.read_bytes()
            if hashlib.sha256(raw).hexdigest() != e["sha256"]:
                sys.exit(f"sha256 mismatch: {f}")
            data = json.loads(gzip.decompress(raw))
            if not isinstance(data, dict) or len(data) != e["string_count"] or not data:
                sys.exit(f"invalid pack: {f}")
            shutil.copy2(f, a.out / f.name)
            langs[e["code"]] = e
            shipped.append(e["code"])

    if not shipped:
        sys.exit("no new language pack to publish")

    manifest = {"schema_version": 1,
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "source_keys": source_keys, "engine": engine,
                "languages": [langs[c] for c in sorted(langs)]}
    (a.out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"shipping {len(shipped)} new pack(s): {', '.join(shipped)}; "
          f"manifest lists {len(langs)} languages")


if __name__ == "__main__":
    main()
