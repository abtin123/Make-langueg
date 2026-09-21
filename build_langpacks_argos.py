#!/usr/bin/env python3
from __future__ import annotations
import gzip, hashlib, json, os, re, shutil, subprocess, sys, time
from pathlib import Path

LANGUAGES = ["ar","az","bg","cs","da","de","el","es","et","fi","fr","he","hi","hu","id","it","ja","ko","lt","lv","ms","nl","pl","pt","ro","ru","sk","sv","tr"]
RTL = {"ar","he"}
ROOT = Path(".")
SOURCE = ROOT / "fa.json"
OUT = ROOT / "output"
CACHE = ROOT / ".argos_cache"
CACHE.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)

def run(*args):
    print("+", " ".join(map(str,args)), flush=True)
    subprocess.run(list(args), check=True)

def install_pair(src, dst):
    import argostranslate.package as pkg
    try:
        pkg.install_package_for_language_pair(src, dst)
    except Exception as exc:
        print(f"package install {src}->{dst}: {exc}", flush=True)
        raise

def uninstall_pair(src, dst):
    try:
        import argostranslate.package as pkg
        for p in list(pkg.get_installed_packages()):
            if p.from_code == src and p.to_code == dst:
                pkg.uninstall(p)
    except Exception as exc:
        print(f"uninstall {src}->{dst}: {exc}", flush=True)

def placeholders(s):
    pats = [r"\{\{[^{}]+\}\}", r"\{[^{}]+\}", r"%\d+\$?[sdif]", r"%[sdif]", r"\$\{[^}]+\}", r"<[^>]+>"]
    out=[]
    for p in pats:
        out += re.findall(p, s)
    return sorted(out)

def validate(src, dst):
    return placeholders(src) == placeholders(dst) and bool(dst.strip()) if src.strip() else not dst.strip()

def save_abl(path, data):
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    tmp = path.with_suffix(".tmp")
    with gzip.open(tmp, "wb", compresslevel=9) as f:
        f.write(raw)
    os.replace(tmp, path)

def sha256(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

def main():
    if not SOURCE.exists():
        raise SystemExit("fa.json not found")
    source=json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    if not isinstance(source, dict) or not source:
        raise SystemExit("invalid fa.json")
    print(f"Source keys: {len(source)}", flush=True)

    run(sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "-q", "argostranslate")
    import argostranslate.package as pkg
    import argostranslate.translate as tr
    pkg.update_package_index()

    # Keep the Persian->English model installed as the permanent pivot.
    install_pair("fa", "en")

    for code in LANGUAGES:
        out_file=OUT / f"lang_{code}.abl"
        cache_file=CACHE / f"{code}.json"
        cache={}
        if cache_file.exists():
            try: cache=json.loads(cache_file.read_text(encoding="utf-8"))
            except Exception: cache={}
        cache={k:v for k,v in cache.items() if k in source and validate(source[k],v)}

        print(f"\n=== {code}: {len(source)-len(cache)} missing ===", flush=True)
        if len(cache) != len(source):
            # Install the target side. If a direct fa->target package exists,
            # use it; otherwise Argos will pivot fa->en->target.
            direct=False
            available=pkg.get_available_packages()
            if any(p.from_code=="fa" and p.to_code==code for p in available):
                try:
                    install_pair("fa", code)
                    direct=True
                except Exception:
                    direct=False
            if not direct:
                install_pair("en", code)

            from_lang=next(x for x in tr.get_installed_languages() if x.code=="fa")
            to_lang=next(x for x in tr.get_installed_languages() if x.code==code)
            translation=from_lang.get_translation(to_lang)
            if translation is None:
                raise RuntimeError(f"No fa->{code} translation path available")

            for key, text in source.items():
                if not text.strip() or key in cache:
                    continue
                last=None
                for attempt in range(3):
                    try:
                        value=translation.translate(text)
                        if validate(text,value):
                            cache[key]=value
                            last=None
                            break
                        last=RuntimeError("placeholder validation failed")
                    except Exception as exc:
                        last=exc
                    time.sleep(0.5*(attempt+1))
                if last is not None:
                    raise RuntimeError(f"{code}:{key}: {last}")
                if len(cache) % 25 == 0:
                    cache_file.write_text(json.dumps(cache,ensure_ascii=False,indent=2),encoding="utf-8")
                    print(f"{code}: {len(cache)}/{len(source)}", flush=True)

            cache_file.write_text(json.dumps(cache,ensure_ascii=False,indent=2),encoding="utf-8")
            if direct:
                uninstall_pair("fa", code)
            else:
                uninstall_pair("en", code)

        # Preserve empty source values exactly and require the exact key set.
        result={k:(cache.get(k,"") if source[k].strip() else "") for k in source}
        missing=[k for k,v in result.items() if source[k].strip() and not v.strip()]
        if missing or set(result)!=set(source):
            raise RuntimeError(f"{code}: incomplete ({len(missing)} missing)")
        save_abl(out_file,result)
        print(f"{code}: DONE {out_file} ({out_file.stat().st_size} bytes)", flush=True)

    packs=[]
    for code in LANGUAGES:
        p=OUT/f"lang_{code}.abl"
        packs.append({
            "language_code":code,
            "language":code,
            "direction":"rtl" if code in RTL else "ltr",
            "string_count":len(source),
            "size":p.stat().st_size,
            "sha256":sha256(p),
            "download_url":f"lang_{code}.abl"
        })
    manifest={"version":"1","source_language":"fa","key_count":len(source),"languages":packs}
    (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    with open("langpacks-manifest.txt","w",encoding="utf-8") as f:
        for p in packs:
            f.write(f'{p["language_code"]} {p["size"]} {p["sha256"]}\n')
    print("ALL LANGUAGE PACKS COMPLETE", flush=True)

if __name__=="__main__":
    main()
