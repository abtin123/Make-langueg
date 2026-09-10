#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Complete all language JSON files from fa.json and prepare release packs."""
from __future__ import annotations
import json, re, sys, time
from pathlib import Path
import urllib.parse, urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / 'assets' / 'local'
ADDITIONS = ROOT / 'source' / 'abtinmaps_localization_additions.json'
EXTRA = ROOT / 'source' / 'abtinmaps_localization_extra.json'
LANGS = ['ar','cs','da','de','el','en','es','fa','fi','fr','he','hi','hu','id','it','ja','ko','nl','no','pl','pt','ro','ru','sv','th','tr','uk','ur','vi','zh']
PH = re.compile(r'\{[a-z_][a-z0-9_]*\}')
TOKEN = re.compile(r'\uE000(\d+)\uE001')

def protect(s: str):
    parts=[]
    def repl(m):
        parts.append(m.group(0)); return f'\uE000{len(parts)-1}\uE001'
    return PH.sub(repl,s),parts

def restore(s, parts):
    return TOKEN.sub(lambda m: parts[int(m.group(1))] if int(m.group(1)) < len(parts) else m.group(0), s)

def google_batch(texts, target):
    if not texts: return []
    q='\n'.join(texts)
    url='https://translate.googleapis.com/translate_a/single?'+urllib.parse.urlencode({'client':'gtx','sl':'fa','tl':target,'dt':'t','q':q})
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(req,timeout=30) as r:
        data=json.loads(r.read().decode('utf-8'))
    joined=''.join(x[0] for x in data[0] if x and x[0])
    out=joined.split('\n')
    if len(out)==len(texts): return out
    result=[]
    for text in texts: result.extend(google_batch([text],target))
    return result

def read(code):
    p=LOCAL/f'{code}.json'
    if not p.exists(): return {}
    return json.loads(p.read_text(encoding='utf-8'))

def main():
    fa=read('fa'); en=read('en')
    for addition_file in (ADDITIONS, EXTRA):
        if not addition_file.exists(): continue
        additions=json.loads(addition_file.read_text(encoding='utf-8'))
        for key,pair in additions.items():
            fa.setdefault(key, pair['fa'])
            en.setdefault(key, pair['en'])
    (LOCAL/'fa.json').write_text(json.dumps(dict(sorted(fa.items())),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (LOCAL/'en.json').write_text(json.dumps(dict(sorted(en.items())),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not fa or set(fa)!=set(en): sys.exit(f'fa/en source mismatch: fa={len(fa)} en={len(en)}')
    for code in LANGS:
        if code in ('fa','en'): continue
        data=read(code)
        todo=[k for k,v in fa.items() if not data.get(k) or data[k]==v]
        print(f'{code}: {len(data)} existing, {len(todo)} to translate')
        for i in range(0,len(todo),30):
            batch=todo[i:i+30]; protected=[]; parts=[]
            for k in batch:
                x,p=protect(fa[k]); protected.append(x); parts.append(p)
            try:
                translated=google_batch(protected,code)
                if len(translated)!=len(batch): raise RuntimeError('translator returned wrong batch size')
                for k,x,p in zip(batch,translated,parts): data[k]=restore(x,p) or en[k]
            except Exception as exc:
                print(f'  batch {i}: {exc}',file=sys.stderr)
                raise SystemExit(f'{code}: translation failed; refusing to publish a partial pack: {exc}')
            time.sleep(0.2)
        for k,v in fa.items():
            if k not in data or not str(data[k]).strip(): data[k]=en[k]
            if PH.findall(v) and set(PH.findall(data[k])) != set(PH.findall(v)): sys.exit(f'{code}: placeholder mismatch in {k}')
        (LOCAL/f'{code}.json').write_text(json.dumps(dict(sorted(data.items())),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for code in LANGS:
        d=read(code)
        if set(d)!=set(fa): sys.exit(f'{code}: key parity failed')
        for k in fa:
            if PH.findall(fa[k]) and set(PH.findall(d[k]))!=set(PH.findall(fa[k])): sys.exit(f'{code}: placeholder parity failed: {k}')
    print(f'COMPLETE: {len(LANGS)} languages x {len(fa)} keys')

if __name__=='__main__': main()
