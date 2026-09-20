#!/usr/bin/env python3
"""
AbtinMaps translation builder - NO API KEY / NO GOOGLE CLOUD.

Input:
    fa.json

Output:
    output/<lang>.json
    output/lang_<lang>.abl
    output/manifest.json

Translation engine:
    Google Translate public web endpoint (no API key).
    This is NOT Google Cloud Translation API.

Important:
- fa and en are local and are NEVER generated.
- Source keys are copied exactly.
- Existing cached translations are reused.
- Placeholders, URLs, HTML tags and printf tokens are protected.
- Failed/empty translations stop the build instead of silently producing bad packs.
- .abl is written in the same gzip(JSON) format used by the previous builder.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

ROOT = Path(__file__).resolve().parent
CACHE_FILE = ROOT / ".translation_cache.json"

LOCAL_LANGUAGES = {"fa", "en"}

TARGETS = [
    "ar", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi",
    "hu", "id", "it", "ja", "ko", "nl", "no", "pl", "pt", "ro",
    "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

# Things that must never be translated.
TOKEN_RE = re.compile(
    r"""
    (
        \{\{[^{}]+\}\}                    # {{name}}
      | \{[^{}]+\}                        # {name}
      | %[0-9$+\-#0 .*]*(?:[hlLzjt]*)(?:[diouxXeEfFgGcrsa%])
      | https?://[^\s<>"']+               # URL
      | <[^>]+>                            # HTML/XML tag
      | \\n|\\r|\\t                       # escaped whitespace
    )
    """,
    re.VERBOSE,
)

SESSION = requests.Session()
SESSION.headers.update(
    {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) "
            "AppleWebKit/537.36 Chrome/131 Safari/537.36"
        ),
        "Accept": "*/*",
    }
)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    tmp.replace(path)


def protect(text: str) -> tuple[str, list[str]]:
    tokens: list[str] = []

    def repl(match: re.Match[str]) -> str:
        token = f"ABTIN_TOKEN_{len(tokens)}_X"
        tokens.append(match.group(0))
        return token

    return TOKEN_RE.sub(repl, text), tokens


def restore(text: str, tokens: list[str]) -> str:
    for i, original in enumerate(tokens):
        text = text.replace(f"ABTIN_TOKEN_{i}_X", original)
    return text


def cache_key(lang: str, source_text: str) -> str:
    return hashlib.sha256(
        f"fa\0{lang}\0{source_text}".encode("utf-8")
    ).hexdigest()


def load_cache() -> dict[str, str]:
    if not CACHE_FILE.exists():
        return {}
    try:
        data = load_json(CACHE_FILE)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_cache(cache: dict[str, str]) -> None:
    save_json(CACHE_FILE, cache)


def google_web_translate(text: str, target: str, retries: int = 5) -> str:
    """
    Uses the public Google Translate web endpoint.
    No API key, OAuth, project ID, or Google Cloud account is required.

    This is an unofficial web endpoint, so the script has retries and
    deliberately throttles requests. Cached translations avoid repeating
    requests on future runs.
    """
    if not text.strip():
        return text

    url = "https://translate.googleapis.com/translate_a/single"

    params = {
        "client": "gtx",
        "sl": "fa",
        "tl": target,
        "dt": "t",
        "q": text,
    }

    last_error: Exception | None = None

    for attempt in range(1, retries + 1):
        try:
            response = SESSION.get(url, params=params, timeout=45)
            response.raise_for_status()
            data = response.json()

            # Expected shape:
            # [[["translated text", "source"], ...], ...]
            parts = []
            for block in data[0]:
                if block and block[0]:
                    parts.append(str(block[0]))

            translated = "".join(parts).strip()

            if translated:
                return translated

            raise RuntimeError("Google web endpoint returned an empty translation.")

        except Exception as exc:
            last_error = exc
            wait = min(2 ** attempt, 30)
            print(
                f"  retry {attempt}/{retries} for {target}: {exc}",
                file=sys.stderr,
            )
            time.sleep(wait)

    raise RuntimeError(
        f"Translation failed for target={target!r}, text={text[:100]!r}: "
        f"{last_error}"
    )


def translate_text(
    source_text: str,
    target: str,
    cache: dict[str, str],
    delay: float,
) -> str:
    key = cache_key(target, source_text)

    if key in cache and cache[key].strip():
        return cache[key]

    protected, tokens = protect(source_text)

    translated = google_web_translate(protected, target)
    translated = restore(translated, tokens)

    # Verify protected tokens survived.
    for token in tokens:
        if token not in translated:
            raise RuntimeError(
                f"Protected token was lost while translating to {target}: "
                f"{token!r} in {source_text!r}"
            )

    translated = translated.strip()

    if not translated:
        raise RuntimeError(
            f"Empty translation for {target}: {source_text!r}"
        )

    cache[key] = translated
    save_cache(cache)

    if delay > 0:
        time.sleep(delay)

    return translated


def write_abl(path: Path, data: dict[str, Any]) -> None:
    """
    Current AbtinMaps builder format:
        UTF-8 compact JSON -> gzip -> .abl
    """
    raw = json.dumps(
        data,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")

    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wb", compresslevel=9) as f:
        f.write(raw)


def read_existing_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    data = load_json(path)
    if not isinstance(data, dict):
        raise RuntimeError(f"{path} must contain a JSON object.")
    return data


def validate(source: dict[str, Any], target: dict[str, Any], lang: str) -> None:
    source_keys = set(source)
    target_keys = set(target)

    missing = sorted(source_keys - target_keys)
    extra = sorted(target_keys - source_keys)

    if missing or extra:
        msg = [f"{lang}: key mismatch."]
        if missing:
            msg.append(f"missing={len(missing)}")
            msg.extend(f"  MISSING: {x}" for x in missing[:20])
        if extra:
            msg.append(f"extra={len(extra)}")
            msg.extend(f"  EXTRA: {x}" for x in extra[:20])
        raise RuntimeError("\n".join(msg))

    for key, value in target.items():
        if isinstance(value, str) and not value.strip():
            raise RuntimeError(
                f"{lang}: empty translation at key {key!r}"
            )


def build_language(
    source: dict[str, Any],
    lang: str,
    output: Path,
    cache: dict[str, str],
    delay: float,
) -> None:
    if lang in LOCAL_LANGUAGES:
        raise RuntimeError(
            f"{lang} is local. fa/en must not be generated or modified."
        )

    target_path = output / f"{lang}.json"
    existing = read_existing_json(target_path)
    target: dict[str, Any] = {}

    total = len(source)
    changed = 0
    reused = 0

    for index, (key, value) in enumerate(source.items(), start=1):
        # Non-string values are copied unchanged.
        if not isinstance(value, str):
            target[key] = value
            continue

        if not value.strip():
            target[key] = value
            continue

        # Do NOT trust an old output file by key alone: the Persian source
        # text may have changed while the key stayed the same. The cache key
        # includes the current Persian text, so only an exact source-text
        # match is reused.
        cache_id = cache_key(lang, value)
        if cache_id in cache and cache[cache_id].strip():
            target[key] = cache[cache_id]
            reused += 1
            continue

        translated = translate_text(
            source_text=value,
            target=lang,
            cache=cache,
            delay=delay,
        )
        target[key] = translated
        changed += 1

        print(
            f"[{lang}] {index}/{total}: {key}",
            flush=True,
        )

    validate(source, target, lang)

    save_json(target_path, target)
    write_abl(output / f"lang_{lang}.abl", target)

    print(
        f"OK {lang}: {total} keys "
        f"(translated={changed}, reused={reused})",
        flush=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build AbtinMaps language packs without an API key."
    )
    parser.add_argument(
        "--input",
        default="fa.json",
        help="Persian source JSON (default: fa.json)",
    )
    parser.add_argument(
        "--output",
        default="dist",
        help="Output directory (default: dist)",
    )
    parser.add_argument(
        "--targets",
        nargs="*",
        default=TARGETS,
        help="Languages to build. fa/en are forbidden.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.25,
        help="Delay between web translation requests (default: 0.25s)",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Ignore the translation cache for this run.",
    )
    args = parser.parse_args()

    source_path = Path(args.input)
    output = Path(args.output)

    if not source_path.exists():
        raise FileNotFoundError(f"Source file not found: {source_path}")

    source = load_json(source_path)

    if not isinstance(source, dict):
        raise RuntimeError("fa.json must contain a JSON object.")

    for lang in args.targets:
        if lang in LOCAL_LANGUAGES:
            raise RuntimeError(
                f"Invalid target {lang!r}: fa and en are local."
            )

    if args.no_cache and CACHE_FILE.exists():
        CACHE_FILE.unlink()

    cache = load_cache()

    print(f"Source: {source_path}")
    print(f"Source keys: {len(source)}")
    print(f"Targets: {', '.join(args.targets)}")
    print("Translation: Google Translate public web endpoint")
    print("API key: NONE")
    print()

    output.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, Any] = {
        "source_language": "fa",
        "source_file": source_path.name,
        "source_keys": len(source),
        "targets": {},
    }

    for lang in args.targets:
        build_language(
            source=source,
            lang=lang,
            output=output,
            cache=cache,
            delay=args.delay,
        )

        abl = output / f"lang_{lang}.abl"

        manifest["targets"][lang] = {
            "keys": len(source),
            "json": f"{lang}.json",
            "abl": abl.name,
            "bytes": abl.stat().st_size,
            "sha256": hashlib.sha256(abl.read_bytes()).hexdigest(),
        }

    save_json(output / "manifest.json", manifest)

    print()
    print("========================================")
    print("Translation build completed successfully")
    print(f"Languages: {len(args.targets)}")
    print(f"Keys:      {len(source)}")
    print(f"Output:    {output.resolve()}")
    print("========================================")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
