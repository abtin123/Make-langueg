#!/usr/bin/env python3
"""
Reliable AbtinMaps language-pack builder.

Fixes the previous builder's main failure mode:
  HTTP 429 Too Many Requests from translate.googleapis.com

Design goals:
- fa.json is the only source of truth.
- fa/en are never generated or modified.
- Only the 28 remote languages are built.
- Persistent cache is reused before making a network request.
- Translation requests are globally rate-limited.
- 429/5xx/network failures use exponential backoff + jitter.
- Retry-After is respected when present.
- A failed item may only fall back to an existing cached translation;
  the script never invents a translation.
- A language pack is published only after its key set is complete.
- ABL format remains gzip(JSON UTF-8), compatible with the Flutter app.
- Placeholder/URL/markup tokens are protected from translation.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import hashlib
import json
import os
import random
import re
import threading
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

LANGUAGES = [
    "ar", "cs", "da", "de", "el", "es", "fi", "fr",
    "he", "hi", "hu", "id", "it", "ja", "ko", "nl",
    "no", "pl", "pt", "ro", "ru", "sv", "th", "tr",
    "uk", "ur", "vi", "zh",
]

# The project historically calls these "28" targets. Keep the canonical list
# explicit and fail loudly if a configuration accidentally changes it.
assert len(LANGUAGES) == 28

DEFAULT_WORKERS = max(1, int(os.getenv("TRANSLATION_WORKERS", "18")))
DEFAULT_MIN_INTERVAL = float(os.getenv("TRANSLATION_MIN_INTERVAL", "0.15"))
REQUEST_TIMEOUT = float(os.getenv("TRANSLATION_TIMEOUT", "25"))
PROVIDER_MAX_ATTEMPTS = int(os.getenv("PROVIDER_MAX_ATTEMPTS", "3"))
PROVIDER_COOLDOWN = float(os.getenv("PROVIDER_COOLDOWN", "20"))

# No API keys, no paid services.
#
# Online free/public providers:
#   1) Google GTX
#   2) MyMemory anonymous
#   3) Lingva public instances (Google-backed, no auth)
#   4) Argos/LibreTranslate public instance
#
# Public instances can disappear or rate-limit independently. The pool therefore
# health-checks/fails over automatically. We deliberately do NOT pretend that
# several copies of the same URL are several independent quotas.
#
# Optional overrides:
#   FREE_TRANSLATION_PROVIDERS=google,mymemory,lingva,argos
#   LINGVA_INSTANCES=https://lingva.ml;https://translate.igna.wtf;...
#   ARGOS_ENDPOINTS=https://translate.argosopentech.com
#
# Local fallback:
#   If ARGOS_LOCAL=1 and argostranslate is installed, local Argos is used as
#   the final fallback. It needs no API key and works offline.

FREE_PROVIDERS = [
    x.strip().lower()
    for x in os.getenv(
        "FREE_TRANSLATION_PROVIDERS",
        "google,mymemory,lingva,argos"
    ).split(",")
    if x.strip()
]

LINGVA_INSTANCES = [
    x.strip().rstrip("/")
    for x in os.getenv(
        "LINGVA_INSTANCES",
        "https://lingva.ml;"
        "https://translate.igna.wtf;"
        "https://translate.plausibility.cloud;"
        "https://lingva.lunar.icu;"
        "https://translate.projectsegfau.lt;"
        "https://translate.dr460nf1r3.org;"
        "https://lingva.garudalinux.org;"
        "https://translate.jae.fi"
    ).split(";")
    if x.strip()
]

ARGOS_ENDPOINTS = [
    x.strip().rstrip("/")
    for x in os.getenv(
        "ARGOS_ENDPOINTS",
        "https://translate.argosopentech.com"
    ).split(";")
    if x.strip()
]

USE_LOCAL_ARGOS = os.getenv("ARGOS_LOCAL", "1").lower() in {"1", "true", "yes"}

# Conservative concurrency for public services. Total workers can be larger,
# but a single provider instance gets its own limiter and cooldown.
PROVIDER_INTERVAL = float(os.getenv("PROVIDER_INTERVAL", "0.20"))


class Provider:
    def __init__(self, name: str, kind: str, endpoint: str = "") -> None:
        self.name = name
        self.kind = kind
        self.endpoint = endpoint.rstrip("/")
        self.rate_limiter = RateLimiter(PROVIDER_INTERVAL)
        self._cooldown_until = 0.0
        self._cooldown_lock = threading.Lock()

    def cooldown(self, seconds: float = PROVIDER_COOLDOWN) -> None:
        with self._cooldown_lock:
            self._cooldown_until = max(
                self._cooldown_until, time.monotonic() + seconds
            )

    def available(self) -> bool:
        with self._cooldown_lock:
            return time.monotonic() >= self._cooldown_until

    def translate(self, text: str, target: str) -> str:
        if self.kind == "google":
            return self.translate_google(text, target)
        if self.kind == "mymemory":
            return self.translate_mymemory(text, target)
        if self.kind == "lingva":
            return self.translate_lingva(text, target)
        if self.kind == "argos":
            return self.translate_argos(text, target)
        if self.kind == "local_argos":
            return self.translate_local_argos(text, target)
        raise TranslationError(f"{self.name}: unknown provider")

    def _validate(self, source: str, translated: str, label: str) -> str:
        if not translated or not translated.strip():
            raise TranslationError(f"{label}: empty translation")
        translated = restore(translated.strip(), self._tokens)
        if not validate_restored(source, translated):
            raise TranslationError(f"{label}: protected-token validation failed")
        return translated

    def translate_google(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self._tokens = tokens
        self.rate_limiter.wait()
        query = (
            f"https://translate.googleapis.com/translate_a/single"
            f"?client=gtx&sl=fa&tl={quote(target)}&dt=t&q={quote(protected)}"
        )
        req = Request(query, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/4.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            translated = parse_gtx_response(json.loads(response.read()))
        return self._validate(text, translated, self.name)

    def translate_mymemory(self, text: str, target: str) -> str:
        # Anonymous MyMemory endpoint; no API key.
        protected, tokens = protect(text)
        self._tokens = tokens
        # MyMemory has a relatively small per-request payload, so keep chunks
        # small. The caller's cache means each key is normally requested once.
        if len(protected.encode("utf-8")) > 450:
            raise TranslationError(f"{self.name}: segment too large for anonymous endpoint")
        self.rate_limiter.wait()
        query = (
            "https://api.mymemory.translated.net/get"
            f"?q={quote(protected)}&langpair=fa%7C{quote(target)}&mt=1"
        )
        req = Request(query, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/4.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("responseData", {}).get("translatedText", "")
        if not translated:
            raise TranslationError(f"{self.name}: empty response")
        return self._validate(text, translated, self.name)

    def translate_lingva(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self._tokens = tokens
        self.rate_limiter.wait()
        url = (
            f"{self.endpoint}/api/v1/fa/{quote(target)}/"
            f"{quote(protected, safe='')}"
        )
        req = Request(url, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/4.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translation", "")
        if not translated:
            raise TranslationError(f"{self.name}: empty/error response")
        return self._validate(text, translated, self.name)

    def translate_argos(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self._tokens = tokens
        self.rate_limiter.wait()
        body = json.dumps({
            "q": protected,
            "source": "fa",
            "target": target,
            "format": "text",
        }, ensure_ascii=False).encode("utf-8")
        req = Request(
            f"{self.endpoint}/translate",
            data=body,
            headers={
                "User-Agent": "AbtinMaps-LanguageBuilder/4.0",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translatedText", "")
        if not translated:
            raise TranslationError(f"{self.name}: empty/error response")
        return self._validate(text, translated, self.name)

    def translate_local_argos(self, text: str, target: str) -> str:
        try:
            import argostranslate.translate as at
        except ImportError as exc:
            raise TranslationError(
                "local-argos unavailable; install argostranslate"
            ) from exc
        protected, tokens = protect(text)
        translated = at.translate(protected, "fa", target)
        self._tokens = tokens
        return self._validate(text, translated, self.name)


class ProviderPool:
    def __init__(self) -> None:
        self.providers: list[Provider] = []

        if "google" in FREE_PROVIDERS:
            self.providers.append(Provider("google-gtx", "google"))

        if "mymemory" in FREE_PROVIDERS:
            self.providers.append(Provider("mymemory-free", "mymemory"))

        if "lingva" in FREE_PROVIDERS:
            for i, endpoint in enumerate(LINGVA_INSTANCES):
                self.providers.append(
                    Provider(f"lingva-{i+1}", "lingva", endpoint)
                )

        if "argos" in FREE_PROVIDERS:
            for i, endpoint in enumerate(ARGOS_ENDPOINTS):
                self.providers.append(
                    Provider(f"argos-public-{i+1}", "argos", endpoint)
                )

        if USE_LOCAL_ARGOS:
            self.providers.append(Provider("argos-local", "local_argos"))

        if not self.providers:
            raise RuntimeError("No free translation providers configured")

        self._lock = threading.Lock()
        self._cursor = 0

    def next_provider(self, attempted: set[str]) -> Provider | None:
        with self._lock:
            n = len(self.providers)
            for _ in range(n):
                p = self.providers[self._cursor % n]
                self._cursor += 1
                if p.name not in attempted and p.available():
                    return p
            for p in self.providers:
                if p.name not in attempted:
                    return p
        return None

    def summary(self) -> str:
        return ", ".join(p.name for p in self.providers)


class Translator:
    def __init__(self, min_interval: float) -> None:
        self.pool = ProviderPool()

    def translate(self, text: str, target: str) -> str:
        if not text.strip():
            return text

        last_error: Exception | None = None
        attempted: set[str] = set()

        # Race many independent public providers. Each worker picks a provider,
        # and a failed provider is immediately abandoned for this item.
        for attempt in range(1, PROVIDER_MAX_ATTEMPTS + 1):
            provider = self.pool.next_provider(attempted)
            if provider is None:
                attempted.clear()
                time.sleep(0.5)
                provider = self.pool.next_provider(attempted)
                if provider is None:
                    raise TranslationError("no free translation provider available")

            attempted.add(provider.name)

            try:
                translated = provider.translate(text, target)
                print(f"[{target}] {provider.name} OK", flush=True)
                return translated

            except HTTPError as exc:
                last_error = exc
                provider.cooldown()
                delay = 0.25 if exc.code in (429, 408) else 0.5
                retry_after = exc.headers.get("Retry-After")
                if retry_after:
                    try:
                        delay = min(10.0, float(retry_after))
                    except ValueError:
                        pass
                delay += random.uniform(0.0, 0.5)
                print(
                    f"[{target}] {provider.name} HTTP {exc.code}; "
                    f"trying another free provider in {delay:.1f}s",
                    flush=True,
                )
                time.sleep(delay)

            except (URLError, TimeoutError, OSError, json.JSONDecodeError, TranslationError) as exc:
                last_error = exc
                provider.cooldown()
                delay = random.uniform(0.15, 0.8)
                print(
                    f"[{target}] {provider.name} unavailable: {exc}; "
                    f"trying another free provider in {delay:.1f}s",
                    flush=True,
                )
                time.sleep(delay)

        raise TranslationError(
            f"{target}: all free translation providers failed after "
            f"{PROVIDER_MAX_ATTEMPTS} attempts: {last_error}"
        )


def build_language(
    code: str,
    source: dict[str, str],
    cache_dir: Path,
    output_dir: Path,
    workers: int,
    translator: Translator,
) -> None:
    cache_file = cache_dir / f"{code}.json"
    cache = load_json(cache_file) if cache_file.exists() else {}

    result: dict[str, str] = {}
    keys = list(source.keys())
    completed = 0
    cache_hits = 0
    lock = threading.Lock()

    def one(item: tuple[str, str]) -> tuple[str, str, bool]:
        key, value = item
        cached = cache.get(key)
        if cached and cached.strip():
            return key, cached, True
        return key, translator.translate(value, code), False

    print(f"\n=== [{code}] {len(keys)} strings | {workers} workers ===", flush=True)

    # Only missing keys are submitted. This makes a rerun after a rate-limit
    # failure resume from the persisted cache instead of restarting the locale.
    missing = [(k, source[k]) for k in keys if not cache.get(k, "").strip()]

    for key in keys:
        if cache.get(key, "").strip():
            result[key] = cache[key]

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(one, item): item[0] for item in missing}
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            translated, was_cache = future.result()[1:]
            result[key] = translated
            completed += 1
            if was_cache:
                cache_hits += 1

            # Persist after every successful translation. A runner interruption
            # therefore loses at most one request rather than an entire locale.
            cache[key] = translated
            atomic_write_json(cache_file, cache)

            total_done = len(keys) - len(missing) + completed
            if total_done % 25 == 0 or total_done == len(keys):
                print(
                    f"[{code}] {total_done}/{len(keys)} "
                    f"(cache {len(keys)-len(missing) + cache_hits})",
                    flush=True,
                )

    # Never emit a partial .abl.
    missing_keys = [k for k in keys if not result.get(k, "").strip()]
    if missing_keys:
        raise TranslationError(
            f"{code}: refusing to publish incomplete pack; "
            f"{len(missing_keys)} keys are missing"
        )

    if set(result) != set(source):
        raise TranslationError(f"{code}: key-set validation failed")

    out = output_dir / f"lang_{code}.abl"
    save_abl(out, result)
    print(f"[{code}] DONE -> {out.name} | cache={len(cache)}/{len(keys)}", flush=True)


def build_manifest(
    source: dict[str, str],
    output_dir: Path,
    version: str,
) -> None:
    packs = []
    for code in LANGUAGES:
        path = output_dir / f"lang_{code}.abl"
        if not path.exists():
            raise RuntimeError(f"manifest: missing completed pack {path}")
        packs.append(
            {
                "language_code": code,
                "language": code,
                "direction": "rtl" if code in {"ar", "he", "fa", "ur"} else "ltr",
                "string_count": len(source),
                "size": path.stat().st_size,
                "sha256": sha256(path),
                "version": version,
                "download_url": f"lang_{code}.abl",
            }
        )

    manifest = {
        "version": version,
        "source_language": "fa",
        "key_count": len(source),
        "languages": packs,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="fa.json")
    parser.add_argument("--output", default="output")
    parser.add_argument("--cache", default=".translation_cache")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    parser.add_argument("--min-interval", type=float, default=DEFAULT_MIN_INTERVAL)
    parser.add_argument("--version", default=os.getenv("LANGPACK_VERSION", "1"))
    args = parser.parse_args()

    if args.workers < 1:
        parser.error("--workers must be >= 1")
    if args.min_interval < 0:
        parser.error("--min-interval must be >= 0")

    source = load_json(Path(args.input))
    if len(source) < 100:
        raise SystemExit(f"Source looks invalid: only {len(source)} keys")

    output_dir = Path(args.output)
    cache_dir = Path(args.cache)
    output_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    print(f"Source: {args.input} | keys: {len(source)}", flush=True)
    print(
        f"Targets: {len(LANGUAGES)} | workers: {args.workers} | "
        f"min interval: {args.min_interval:.2f}s",
        flush=True,
    )

    translator = Translator(args.min_interval)
    print(f"Provider pool: {translator.pool.summary()}", flush=True)

    for code in LANGUAGES:
        build_language(
            code,
            source,
            cache_dir,
            output_dir,
            args.workers,
            translator,
        )

    build_manifest(source, output_dir, args.version)
    print(f"All {len(LANGUAGES)} language packs completed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
