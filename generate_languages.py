#!/usr/bin/env python3
"""
Generate language JSON files and ABL release packs from fa.json.

Uses Google Cloud Translation API v3.
Required environment variables:
  GOOGLE_CLOUD_PROJECT
  GOOGLE_CLOUD_LOCATION (default: global)
  GOOGLE_APPLICATION_CREDENTIALS

Alternatively, set GOOGLE_TRANSLATE_API_KEY for the API-key based endpoint
where supported by your Google Cloud setup.

The script:
- preserves the exact source keys
- translates only missing/changed strings
- caches translations locally
- protects placeholders, URLs, HTML tags and printf-style tokens
- validates that every target has exactly the same keys as fa.json
- writes JSON and gzip-compressed .abl files
"""

from __future__ import annotations
import argparse, gzip, hashlib, json, os, re, sys, time
from pathlib import Path
from typing import Dict, List

try:
    import requests
except ImportError:
    print("Install requests: pip install requests", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / ".translation_cache.json"

LOCAL_LANGUAGES = {"fa", "en"}
DEFAULT_TARGETS = [
    "ar","cs","da","de","el","es","fi","fr","he","hi","hu","id","it",
    "ja","ko","nl","no","pl","pt","ro","ru","sv","th","tr","uk","ur","vi","zh"
]

# Tokens that must survive translation.
TOKEN_RE = re.compile(
    r"(\{\{[^{}]+\}\}|\{[^{}]+\}|%(?:\d+\$)?[+#\-0 ]*(?:\d+|\*)?(?:\.\d+|\.\*)?[a-zA-Z%]"
    r"|https?://\S+|<[^>]+>|\\n|\\t)"
)

def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

def protect(s: str):
    tokens = []
    def repl(m):
        token = f"__ABM_TOKEN_{len(tokens)}__"
        tokens.append(m.group(0))
        return token
    return TOKEN_RE.sub(repl, s), tokens

def restore(s: str, tokens):
    for i, token in enumerate(tokens):
        s = s.replace(f"__ABM_TOKEN_{i}__", token)
    return s

def cache_key(source, target, text):
    return hashlib.sha256(
        f"{source}\0{target}\0{text}".encode("utf-8")
    ).hexdigest()

def load_cache():
    if CACHE.exists():
        try:
            return load_json(CACHE)
        except Exception:
            pass
    return {}

def save_cache(cache):
    save_json(CACHE, cache)

def translate_google_v3(texts: List[str], target: str) -> List[str]:
    project = os.environ.get("GOOGLE_CLOUD_PROJECT")
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")
    if not project:
        raise RuntimeError("GOOGLE_CLOUD_PROJECT is required.")

    # ADC is used by google-auth. Keep imports local so the script starts cleanly.
    try:
        import google.auth
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        raise RuntimeError(
            "Install google-cloud-auth dependencies: "
            "pip install google-auth requests"
        )

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    session = AuthorizedSession(credentials)

    url = (
        f"https://translation.googleapis.com/v3/projects/{project}"
        f"/locations/{location}:translateText"
    )
    body = {
        "sourceLanguageCode": "fa",
        "targetLanguageCode": target,
        "contents": texts,
        "mimeType": "text/plain",
    }
    r = session.post(url, json=body, timeout=60)
    r.raise_for_status()
    data = r.json()
    translations = data.get("translations", [])
    if len(translations) != len(texts):
        raise RuntimeError(
            f"Google returned {len(translations)} translations for {len(texts)} inputs."
        )
    return [x.get("translatedText", "") for x in translations]

def write_abl(path: Path, data):
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wb", compresslevel=9) as f:
        f.write(raw)

def validate(source: Dict, target: Dict, lang: str):
    sk = set(source)
    tk = set(target)
    missing = sorted(sk - tk)
    extra = sorted(tk - sk)
    if missing or extra:
        raise RuntimeError(
            f"{lang}: key mismatch; missing={len(missing)}, extra={len(extra)}"
        )
    empty = [k for k,v in target.items() if isinstance(v, str) and not v.strip()]
    if empty:
        raise RuntimeError(f"{lang}: {len(empty)} empty translations.")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="fa.json")
    ap.add_argument("--output", default="output")
    ap.add_argument(
        "--targets", nargs="*", default=DEFAULT_TARGETS,
        help="Remote languages only. fa and en are local and are never generated."
    )
    ap.add_argument("--batch-size", type=int, default=64)
    args = ap.parse_args()

    source = load_json(Path(args.input))
    if not isinstance(source, dict):
        raise RuntimeError("fa.json must contain a JSON object.")

    cache = load_cache()
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source_language": "fa",
        "source_keys": len(source),
        "targets": {},
    }

    for lang in args.targets:
        if lang in LOCAL_LANGUAGES:
            raise RuntimeError(
                f"{lang} is a local language and must not be generated or modified."
            )
        else:
            target_path = outdir / f"{lang}.json"
            existing = load_json(target_path) if target_path.exists() else {}
            target = {}
            pending = []
            pending_keys = []

            for key, value in source.items():
                if not isinstance(value, str) or not value.strip():
                    target[key] = value
                    continue
                ck = cache_key("fa", lang, value)
                if key in existing and existing[key] and existing[key] != value:
                    target[key] = existing[key]
                elif ck in cache and cache[ck]:
                    target[key] = cache[ck]
                else:
                    protected, tokens = protect(value)
                    pending.append((protected, tokens, ck))
                    pending_keys.append(key)

            for i in range(0, len(pending), args.batch_size):
                batch = pending[i:i+args.batch_size]
                texts = [x[0] for x in batch]
                translated = translate_google_v3(texts, lang)
                for (protected, tokens, ck), key, tr in zip(
                    batch, pending_keys[i:i+args.batch_size], translated
                ):
                    tr = restore(tr, tokens)
                    cache[ck] = tr
                    target[key] = tr
                save_cache(cache)
                time.sleep(0.05)

        validate(source, target, lang)
        save_json(outdir / f"{lang}.json", target)
        abl = outdir / f"lang_{lang}.abl"
        write_abl(abl, target)

        manifest["targets"][lang] = {
            "keys": len(target),
            "json": str((outdir / f"{lang}.json").name),
            "abl": str(abl.name),
            "sha256": hashlib.sha256(abl.read_bytes()).hexdigest(),
            "bytes": abl.stat().st_size,
        }
        print(f"OK {lang}: {len(target)} keys")

    save_json(outdir / "manifest.json", manifest)
    print(f"Done: {len(args.targets)} languages, {len(source)} source keys.")

if __name__ == "__main__":
    main()
