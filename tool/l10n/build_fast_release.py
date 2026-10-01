#!/usr/bin/env python3
from __future__ import annotations

import gzip, hashlib, json, os, re, time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "lib/core/localization/app_localizations.dart"
OUT = ROOT / "tool/l10n/out"
CACHE = ROOT / "tool/l10n/.fast_cache"

LANGUAGES = ["ar","cs","da","de","el","es","fi","fr","he","hi","hu","id","it","ja","ko","nl","no","pl","pt","ro","ru","sv","th","tr","uk","ur","vi","zh"]
RTL = {"ar","he","fa","ur"}
TARGET = {"zh":"zh-CN"}

TOKEN_RE = re.compile(r"__ABTIN_[A-Z0-9_]+__")
PAIR_PATTERNS = (
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", re.S),
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*"((?:\\.|[^"\\])*)"", re.S),
    re.compile(r""((?:\\.|[^"\\])*)"\s*:\s*'((?:\\.|[^'\\])*)'", re.S),
    re.compile(r""((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"", re.S),
)

def unescape(v):
    return v.replace(r"\\","\\").replace(r"\'","'").replace(r'\"','"').replace(r"\n","\n").replace(r"\r","\r").replace(r"\t","\t")

def extract_block(text, lang):
    marker = f"    '{lang}': {{"
    start = text.index(marker) + len(marker)
    end = text.index("    'en': {", start) if lang == "fa" else text.index("\n  };", start)
    return text[start:end]

def extract(text, lang):
    out = {}
    for pat in PAIR_PATTERNS:
        for m in pat.finditer(extract_block(text, lang)):
            k,v = map(unescape, m.groups())
            out[k] = v
    return dict(sorted(out.items()))

def protect(s):
    tokens = {}
    i = 0
    patterns = [r"\{\{[^{}]+\}\}", r"\{[^{}]+\}", r"%\d+\$?[sdif]", r"%[sdif]", r"\$\{[^}]+\}", r"<[^>]+>"]
    for pat in patterns:
        def repl(m):
            nonlocal i
            t = f"__ABTIN_TOKEN_{i}__"; i += 1; tokens[t] = m.group(0); return t
        s = re.sub(pat, repl, s)
    return s, tokens

def restore(s, tokens):
    for k,v in tokens.items(): s = s.replace(k,v)
    return s

def google_batch(items, target):
    # Each item is protected before joining. Newlines are separators between strings.
    protected, maps = [], []
    for key, text in items:
        p,t = protect(text)
        p = p.replace("\n", "__ABTIN_NL__")
        protected.append(p)
        maps.append(t)
    joined = "\n__ABTIN_ITEM_BREAK__\n".join(protected)
    data = urlencode({"client":"gtx","sl":"fa","tl":TARGET.get(target,target),"dt":"t","q":joined}).encode()
    req = Request("https://translate.googleapis.com/translate_a/single", data=data,
                  headers={"User-Agent":"AbtinMaps-LanguageBuilder/7.0","Accept":"application/json","Content-Type":"application/x-www-form-urlencoded"})
    with urlopen(req, timeout=35) as r:
        payload = json.loads(r.read())
    parts = payload[0] if isinstance(payload, list) else []
    translated = "".join(p[0] for p in parts if isinstance(p,list) and p and isinstance(p[0],str))
    chunks = translated.split("__ABTIN_ITEM_BREAK__")
    if len(chunks) != len(items):
        # Google can collapse whitespace around separators; use the sentence list as a fallback.
        raise RuntimeError(f"batch split mismatch: got {len(chunks)} expected {len(items)}")
    result = {}
    for (key, original), chunk, toks in zip(items, chunks, maps):
        chunk = chunk.strip().replace("__ABTIN_NL__", "\n")
        chunk = restore(chunk, toks)
        if not chunk or "ABTIN_ITEM_BREAK" in chunk or "ABTIN_TOKEN" in chunk:
            raise RuntimeError(f"invalid translated segment for {key}")
        result[key] = chunk
    return result

def translate_one(key, text, target):
    for attempt in range(4):
        try:
            return google_batch([(key,text)], target)[key]
        except Exception:
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"translation failed: {target}:{key}")

def load_cache(code):
    p = CACHE / f"{code}.json"
    if p.exists():
        try:
            d=json.loads(p.read_text(encoding="utf-8"))
            return d if isinstance(d,dict) else {}
        except Exception: pass
    return {}

def save_cache(code, data):
    CACHE.mkdir(parents=True, exist_ok=True)
    p=CACHE/f"{code}.json"
    tmp=p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    os.replace(tmp,p)

def write_abl(code,data):
    OUT.mkdir(parents=True,exist_ok=True)
    raw=json.dumps(dict(sorted(data.items())),ensure_ascii=False,separators=(",",":")).encode()
    with gzip.open(OUT/f"lang_{code}.abl.tmp","wb",compresslevel=9) as f: f.write(raw)
    os.replace(OUT/f"lang_{code}.abl.tmp",OUT/f"lang_{code}.abl")

def sha256(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
    return h.hexdigest()

def main():
    source=SOURCE.read_text(encoding="utf-8")
    fa=extract(source,"fa"); en=extract(source,"en")
    if len(fa)<100 or set(fa)!=set(en): raise SystemExit(f"bad extraction fa={len(fa)} en={len(en)}")
    OUT.mkdir(parents=True,exist_ok=True); CACHE.mkdir(parents=True,exist_ok=True)
    workers=int(os.getenv("TRANSLATION_WORKERS","1"))
    batch_size=int(os.getenv("TRANSLATION_BATCH_SIZE","18"))
    print(f"Source keys: {len(fa)} | packs: {len(LANGUAGES)} | batch: {batch_size}",flush=True)
    completed=[]
    for code in LANGUAGES:
        cache=load_cache(code)
        missing=[(k,v) for k,v in fa.items() if k not in cache or not str(cache[k]).strip()]
        print(f"[{code}] cached={len(cache)} missing={len(missing)}",flush=True)
        failed=[]
        for pos in range(0,len(missing),batch_size):
            batch=missing[pos:pos+batch_size]
            ok=False
            for attempt in range(5):
                try:
                    got=google_batch(batch,code)
                    cache.update(got); save_cache(code,cache); ok=True; break
                except HTTPError as e:
                    print(f"[{code}] batch {pos}: HTTP {e.code} attempt {attempt+1}",flush=True)
                    time.sleep(min(20,2**attempt))
                except Exception as e:
                    print(f"[{code}] batch {pos}: {e} attempt {attempt+1}",flush=True)
                    time.sleep(min(15,2**attempt))
            if not ok:
                failed.extend(k for k,_ in batch)
        if failed:
            # Final per-string retry for only failed segments.
            for k in failed[:]:
                try:
                    cache[k]=translate_one(k,fa[k],code); failed.remove(k); save_cache(code,cache)
                except Exception: pass
        bad=[k for k,v in fa.items() if v.strip() and (k not in cache or not str(cache[k]).strip())]
        if bad:
            print(f"[{code}] INCOMPLETE {len(bad)} keys; not publishing this pack",flush=True)
            continue
        write_abl(code,{k:str(cache[k]) for k in fa})
        completed.append(code)
        print(f"[{code}] DONE {len(fa)} keys",flush=True)
    if set(completed)!=set(LANGUAGES):
        raise SystemExit("Missing packs: "+",".join(sorted(set(LANGUAGES)-set(completed))))
    packs=[]
    for code in LANGUAGES:
        p=OUT/f"lang_{code}.abl"
        packs.append({"language_code":code,"direction":"rtl" if code in RTL else "ltr","string_count":len(fa),"size":p.stat().st_size,"sha256":sha256(p),"download_url":p.name})
    manifest={"version":os.getenv("LANGPACK_VERSION","1"),"source_language":"fa","key_count":len(fa),"language_count":len(packs),"languages":packs}
    (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("ALL 28 LANGUAGE PACKS READY",flush=True)

if __name__=="__main__": main()
