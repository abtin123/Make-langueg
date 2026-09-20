#!/usr/bin/env python3
import argparse
import gzip
import hashlib
import json
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

LOCAL_LANGUAGES = {"fa", "en"}
TARGETS = [
    "ar", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi",
    "hu", "id", "it", "ja", "ko", "nl", "no", "pl", "pt", "ro",
    "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "fa.json"
DIST = ROOT / "dist"
CACHE_FILE = ROOT / ".translation_cache.json"

MAX_WORKERS = 8
TIMEOUT = 45
RETRIES = 5
RETRY_DELAY = 1.5

_thread = threading.local()
cache_lock = threading.Lock()
print_lock = threading.Lock()

PROTECT_RE = re.compile(
    r"(\{\{[^{}]+\}\}|\{[^{}]+\}|"
    r"%[-+#0 ]*(?:\d+|\*)?(?:\.\d+|\.\*)?[diouxXeEfFgGcrsa%]|"
    r"https?://[^\s<>\"]+|"
    r"</?[A-Za-z][^>]*>|\\[nrt])"
)

def log(s):
    with print_lock:
        print(s, flush=True)

def get_session():
    if not hasattr(_thread, "session"):
        s = requests.Session()
        s.headers.update({"User-Agent": "Mozilla/5.0 AbtinMaps-Translation-Builder"})
        _thread.session = s
    return _thread.session

def load_json(path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)

def atomic_json(path, data):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    tmp.replace(path)

def cache_key(lang, text):
    return hashlib.sha256(f"{lang}\0{text}".encode("utf-8")).hexdigest()

def load_cache():
    if not CACHE_FILE.exists():
        return {}
    try:
        data = load_json(CACHE_FILE)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def save_cache(cache):
    with cache_lock:
        atomic_json(CACHE_FILE, cache)

def protect(text):
    items = []
    def repl(m):
        token = f"__ABTIN_TOKEN_{len(items)}__"
        items.append(m.group(0))
        return token
    return PROTECT_RE.sub(repl, text), items

def restore(text, items):
    for i, original in enumerate(items):
        token = f"__ABTIN_TOKEN_{i}__"
        if token not in text:
            raise RuntimeError(f"Protected token was lost: {original}")
        text = text.replace(token, original)
    return text

def translate(text, lang):
    protected, items = protect(text)
    params = {
        "client": "gtx",
        "sl": "fa",
        "tl": lang,
        "dt": "t",
        "q": protected,
    }

    last_error = None
    for attempt in range(1, RETRIES + 1):
        try:
            r = get_session().get(
                "https://translate.googleapis.com/translate_a/single",
                params=params,
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            data = r.json()
            parts = data[0] if data and isinstance(data[0], list) else []
            result = "".join(
                p[0] for p in parts
                if isinstance(p, list) and p and isinstance(p[0], str)
            ).strip()

            if not result:
                raise RuntimeError("Empty translation")

            result = html_unescape(result)
            return restore(result, items)

        except Exception as e:
            last_error = e
            if attempt < RETRIES:
                time.sleep(RETRY_DELAY * attempt)

    raise RuntimeError(f"{lang}: translation failed after {RETRIES} attempts: {last_error}")

def html_unescape(text):
    import html
    return html.unescape(text)

def translate_item(key, value, lang, cache, index, total):
    if not isinstance(value, str) or not value.strip():
        return key, value, False

    ck = cache_key(lang, value)
    with cache_lock:
        cached = cache.get(ck)

    if isinstance(cached, str) and cached.strip():
        return key, cached, True

    result = translate(value, lang)

    with cache_lock:
        cache[ck] = result

    return key, result, False

def build_language(lang, source, cache):
    target = {}
    total = len(source)
    reused = 0

    log(f"\n=== [{lang}] {total} strings | 8 workers ===")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {
            pool.submit(translate_item, key, value, lang, cache, i, total): (i, key)
            for i, (key, value) in enumerate(source.items(), 1)
        }

        done = 0
        for future in as_completed(futures):
            i, key = futures[future]
            k, value, from_cache = future.result()
            target[k] = value
            done += 1
            if from_cache:
                reused += 1
            if done % 25 == 0 or done == total:
                log(f"[{lang}] {done}/{total} {'(cache ' + str(reused) + ')' if reused else ''}")

    # Preserve source key order exactly.
    target = {key: target[key] for key in source.keys()}

    json_path = DIST / f"{lang}.json"
    abl_path = DIST / f"{lang}.abl"
    json_path.parent.mkdir(parents=True, exist_ok=True)

    atomic_json(json_path, target)

    raw = json.dumps(target, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.open(abl_path, "wb", compresslevel=9) as f:
        f.write(raw)

    log(f"[{lang}] DONE -> {abl_path.name} | cache={reused}/{total}")

    with cache_lock:
        atomic_json(CACHE_FILE, cache)

    return lang, abl_path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", nargs="+", default=TARGETS)
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    if not SOURCE.exists():
        raise SystemExit("fa.json not found")

    targets = [x.lower() for x in args.targets]
    invalid = set(targets) & LOCAL_LANGUAGES
    if invalid:
        raise SystemExit(f"Local languages cannot be generated: {sorted(invalid)}")

    unknown = [x for x in targets if x not in TARGETS]
    if unknown:
        raise SystemExit(f"Unknown target languages: {unknown}")

    source = load_json(SOURCE)
    if not isinstance(source, dict):
        raise SystemExit("fa.json must contain a JSON object")

    cache = {} if args.no_cache else load_cache()
    DIST.mkdir(parents=True, exist_ok=True)

    log(f"Source: fa.json | keys: {len(source)}")
    log(f"Targets: {len(targets)} | workers per language: {MAX_WORKERS}")

    for lang in targets:
        build_language(lang, source, cache)

    manifest = {
        "source": "fa.json",
        "source_language": "fa",
        "local_languages": sorted(LOCAL_LANGUAGES),
        "targets": targets,
        "key_count": len(source),
        "format": "gzip-json-with-abl-extension",
        "files": {}
    }

    for lang in targets:
        p = DIST / f"{lang}.abl"
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        manifest["files"][lang] = {
            "file": p.name,
            "bytes": p.stat().st_size,
            "sha256": digest,
        }

    atomic_json(DIST / "manifest.json", manifest)
    log("\nALL LANGUAGE PACKS BUILT SUCCESSFULLY.")

if __name__ == "__main__":
    main()
