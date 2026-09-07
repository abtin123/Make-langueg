#!/usr/bin/env python3
"""Build language packs using ONLY the existing JSON locale files.

The Persian locale (locales/fa.json) is the canonical key set. No Dart source,
API key, translation service, key generation, or key mutation is used.
"""
from __future__ import annotations
import argparse, gzip, hashlib, json
from datetime import datetime, timezone
from pathlib import Path
from language_catalog import LANGUAGES

def read_flat(path: Path) -> dict[str,str]:
    value=json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in value.items()):
        raise ValueError(f"{path} must be a flat JSON object of string keys and values")
    return value

def build(*, locales_dir: Path, out_dir: Path, download_base: str,
          include_builtins: bool, codes: list[str] | None) -> None:
    source_path=locales_dir/"fa.json"
    if not source_path.exists():
        raise ValueError(f"Missing canonical locale: {source_path}")
    source=read_flat(source_path)
    expected=set(source)
    if not expected:
        raise ValueError("locales/fa.json is empty")

    out_dir.mkdir(parents=True,exist_ok=True)
    languages=[]
    for code,(english_name,native_name,flag,direction) in LANGUAGES.items():
        if codes is not None and code not in codes: continue
        if not include_builtins and code in {"fa","en"}: continue
        path=locales_dir/f"{code}.json"
        if not path.exists(): raise ValueError(f"Missing locale: {path}")
        values=read_flat(path)
        missing=expected-set(values); extra=set(values)-expected
        if missing or extra:
            raise ValueError(f"{code}.json key set differs from locales/fa.json; missing={len(missing)}, extra={len(extra)}")
        if any(not v.strip() for v in values.values()):
            raise ValueError(f"{code}.json contains blank values")
        raw=json.dumps(values,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
        packed=gzip.compress(raw,compresslevel=9,mtime=0)
        fn=f"lang_{code}.abl"; (out_dir/fn).write_bytes(packed)
        languages.append({"language_code":code,"language":native_name,"english_name":english_name,
          "flag":flag,"direction":direction,"version":hashlib.sha256(raw).hexdigest()[:16],
          "string_count":len(values),"size":len(packed),"sha256":hashlib.sha256(packed).hexdigest(),
          "download_url":f"{download_base.rstrip('/')}/{fn}"})
    manifest={"schema_version":2,"generated_at":datetime.now(timezone.utc).isoformat(),
      "app_strings":"non-map-ui","base_language":"fa","string_count":len(source),
      "languages":sorted(languages,key=lambda x:x["language_code"])}
    (out_dir/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"Built {len(languages)} packs with {len(source)} keys directly from existing JSON locales.")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--locales-dir",type=Path,default=Path("locales"))
    p.add_argument("--out",type=Path,default=Path("out"))
    p.add_argument("--download-base",required=True)
    p.add_argument("--include-builtins",action="store_true")
    p.add_argument("--codes",nargs="*",default=None)
    a=p.parse_args()
    build(locales_dir=a.locales_dir,out_dir=a.out,download_base=a.download_base,
          include_builtins=a.include_builtins,codes=a.codes)
if __name__=="__main__": main()
