#!/usr/bin/env python3
"""Validate that language packs are built solely from existing JSON locale files."""
from __future__ import annotations
import argparse, json
from pathlib import Path

def read_flat(path):
    value=json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value,dict), f"{path} is not a JSON object"
    assert all(isinstance(k,str) and isinstance(v,str) for k,v in value.items()), f"{path} is not flat string JSON"
    return value

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--require-complete",action="store_true")
    p.add_argument("--project",type=Path,default=None)
    a=p.parse_args()
    root=Path(__file__).resolve().parents[1]
    locales=root/"locales"
    canonical=read_flat(locales/"fa.json")
    expected=set(canonical)
    assert expected, "fa.json is empty"
    build=(root/"scripts/build.py").read_text(encoding="utf-8")
    workflow=(root/".github/workflows/build-and-publish-langpacks.yml").read_text(encoding="utf-8")
    assert "fa.json" in build
    assert "complete_locales_internal.py" not in workflow
    assert "OPENAI_API_KEY" not in workflow
    assert "base_strings.json" not in workflow
    assert "extract_app_strings.py" not in workflow
    assert "--source" not in workflow
    assert "scripts/build.py" in workflow
    if a.require_complete:
        for path in sorted(locales.glob("*.json")):
            if path.name=="manifest.json": continue
            values=read_flat(path)
            assert set(values)==expected, f"{path.name} key set differs from fa.json"
            assert all(v.strip() for v in values.values()), f"{path.name} has blank values"
    print(f"json_only_contract_ok: {len(expected)} keys")
if __name__=="__main__": main()
