#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import hashlib
import json
import os
import random
import threading
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


LANGUAGES = [
    "ar","az","bg","cs","da","de","el","es","et","fi","fr","he","hi","hu",
    "id","it","ja","ko","lt","lv","ms","nl","pl","pt","ro","ru","sk","sv","tr"
]

DEFAULT_WORKERS = max(1, int(os.getenv("TRANSLATION_WORKERS", "18")))
DEFAULT_MIN_INTERVAL = float(os.getenv("TRANSLATION_MIN_INTERVAL", "0.15"))
REQUEST_TIMEOUT = float(os.getenv("TRANSLATION_TIMEOUT", "25"))
PROVIDER_MAX_ATTEMPTS = max(1, int(os.getenv("PROVIDER_MAX_ATTEMPTS", "3")))
PROVIDER_COOLDOWN = float(os.getenv("PROVIDER_COOLDOWN", "20"))
PROVIDER_INTERVAL = float(os.getenv("PROVIDER_INTERVAL", "0.20"))

FREE_PROVIDERS = [
    x.strip().lower()
    for x in os.getenv(
        "FREE_TRANSLATION_PROVIDERS",
        "google,mymemory,lingva,argos"
    ).split(",") if x.strip()
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
    ).split(";") if x.strip()
]

ARGOS_ENDPOINTS = [
    x.strip().rstrip("/")
    for x in os.getenv(
        "ARGOS_ENDPOINTS",
        "https://translate.argosopentech.com"
    ).split(";") if x.strip()
]

USE_LOCAL_ARGOS = os.getenv("ARGOS_LOCAL", "1").lower() in {"1", "true", "yes"}


class TranslationError(RuntimeError):
    pass


class RateLimiter:
    def __init__(self, interval: float):
        self.interval = max(0.0, interval)
        self.lock = threading.Lock()
        self.next_allowed = 0.0

    def wait(self):
        if self.interval <= 0:
            return
        with self.lock:
            now = time.monotonic()
            delay = max(0.0, self.next_allowed - now)
            self.next_allowed = max(now, self.next_allowed) + self.interval
        if delay:
            time.sleep(delay)


def load_json(path: Path) -> dict[str, str]:
    with path.open("r", encoding="utf-8-sig") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError(f"{path}: expected JSON object")
    result = {}
    for k, v in obj.items():
        if not isinstance(k, str):
            raise ValueError(f"{path}: non-string key")
        if not isinstance(v, str):
            raise ValueError(f"{path}: value for {k!r} is not a string")
        result[k] = v
    return result


def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps(obj, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(tmp, path)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def save_abl(path: Path, data: dict[str, str]) -> None:
    # Preserve the existing .abl contract used by the language pack builder:
    # UTF-8 JSON compressed with gzip.
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.open(tmp, "wb", compresslevel=9) as f:
        f.write(raw)
    os.replace(tmp, path)


def protect(text: str) -> tuple[str, dict[str, str]]:
    tokens: dict[str, str] = {}
    patterns = [
        r"\{\{[^{}]+\}\}",
        r"\{[^{}]+\}",
        r"%\d+\$?[sdif]",
        r"%[sdif]",
        r"\$\{[^}]+\}",
        r"<[^>]+>",
    ]
    counter = 0

    def repl(m):
        nonlocal counter
        token = f"__ABTIN_TOKEN_{counter}__"
        tokens[token] = m.group(0)
        counter += 1
        return token

    protected = text
    for pattern in patterns:
        protected = re.sub(pattern, repl, protected)
    return protected, tokens


def restore(text: str, tokens: dict[str, str]) -> str:
    for token, original in tokens.items():
        text = text.replace(token, original)
    return text


def validate_restored(source: str, translated: str) -> bool:
    _, src_tokens = protect(source)
    _, dst_tokens = protect(translated)
    # Compare actual protected token strings, not generated placeholder IDs.
    src_originals = sorted(src_tokens.values())
    dst_originals = sorted(dst_tokens.values())
    return src_originals == dst_originals


def parse_gtx_response(payload: Any) -> str:
    if not isinstance(payload, list) or not payload:
        raise TranslationError("Google: invalid response")
    chunks = payload[0]
    if not isinstance(chunks, list):
        raise TranslationError("Google: invalid translation array")
    return "".join(
        part[0] for part in chunks
        if isinstance(part, list) and part and isinstance(part[0], str)
    )


class Provider:
    def __init__(self, name: str, kind: str, endpoint: str = ""):
        self.name = name
        self.kind = kind
        self.endpoint = endpoint.rstrip("/")
        self.rate_limiter = RateLimiter(PROVIDER_INTERVAL)
        self._cooldown_until = 0.0
        self._cooldown_lock = threading.Lock()

    def cooldown(self, seconds: float = PROVIDER_COOLDOWN):
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

    def _validate(self, source: str, translated: str, tokens: dict[str, str]) -> str:
        if not translated or not translated.strip():
            raise TranslationError(f"{self.name}: empty translation")
        translated = restore(translated.strip(), tokens)
        if not validate_restored(source, translated):
            raise TranslationError(f"{self.name}: protected-token validation failed")
        return translated

    def translate_google(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        url = (
            "https://translate.googleapis.com/translate_a/single"
            f"?client=gtx&sl=fa&tl={quote(target)}&dt=t&q={quote(protected)}"
        )
        req = Request(url, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/5.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            translated = parse_gtx_response(json.loads(response.read()))
        return self._validate(text, translated, tokens)

    def translate_mymemory(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        # Anonymous endpoint has practical request-size limits.
        if len(protected.encode("utf-8")) > 450:
            raise TranslationError(f"{self.name}: segment too large")
        self.rate_limiter.wait()
        url = (
            "https://api.mymemory.translated.net/get"
            f"?q={quote(protected)}&langpair=fa%7C{quote(target)}&mt=1"
        )
        req = Request(url, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/5.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("responseData", {}).get("translatedText", "")
        return self._validate(text, translated, tokens)

    def translate_lingva(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        url = f"{self.endpoint}/api/v1/fa/{quote(target)}/{quote(protected, safe='')}"
        req = Request(url, headers={
            "User-Agent": "AbtinMaps-LanguageBuilder/5.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translation", "")
        return self._validate(text, translated, tokens)

    def translate_argos(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        body = json.dumps({
            "q": protected, "source": "fa", "target": target, "format": "text"
        }, ensure_ascii=False).encode("utf-8")
        req = Request(
            f"{self.endpoint}/translate",
            data=body,
            headers={
                "User-Agent": "AbtinMaps-LanguageBuilder/5.0",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translatedText", "")
        return self._validate(text, translated, tokens)

    def translate_local_argos(self, text: str, target: str) -> str:
        try:
            import argostranslate.translate as at
        except ImportError as exc:
            raise TranslationError(
                "local Argos is unavailable; install argostranslate"
            ) from exc
        protected, tokens = protect(text)
        translated = at.translate(protected, "fa", target)
        return self._validate(text, translated, tokens)


class ProviderPool:
    def __init__(self):
        self.providers: list[Provider] = []

        if "google" in FREE_PROVIDERS:
            self.providers.append(Provider("google-gtx", "google"))

        if "mymemory" in FREE_PROVIDERS:
            self.providers.append(Provider("mymemory-free", "mymemory"))

        if "lingva" in FREE_PROVIDERS:
            for i, endpoint in enumerate(LINGVA_INSTANCES):
                self.providers.append(Provider(f"lingva-{i+1}", "lingva", endpoint))

        if "argos" in FREE_PROVIDERS:
            for i, endpoint in enumerate(ARGOS_ENDPOINTS):
                self.providers.append(Provider(f"argos-public-{i+1}", "argos", endpoint))

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
    def __init__(self, min_interval: float):
        # min_interval is retained for CLI compatibility. Provider-specific
        # throttling is handled independently by each Provider.
        self.pool = ProviderPool()

    def translate(self, text: str, target: str) -> str:
        if not text.strip():
            return text

        last_error: Exception | None = None
        attempted: set[str] = set()

        for _ in range(PROVIDER_MAX_ATTEMPTS):
            provider = self.pool.next_provider(attempted)
            if provider is None:
                attempted.clear()
                time.sleep(0.5)
                provider = self.pool.next_provider(attempted)
                if provider is None:
                    break

            attempted.add(provider.name)

            try:
                translated = provider.translate(text, target)
                print(f"[{target}] {provider.name} OK", flush=True)
                return translated

            except HTTPError as exc:
                last_error = exc
                provider.cooldown()
                delay = 0.25 if exc.code in (408, 429) else 0.5
                retry_after = exc.headers.get("Retry-After")
                if retry_after:
                    try:
                        delay = min(10.0, float(retry_after))
                    except ValueError:
                        pass
                delay += random.uniform(0.0, 0.5)
                print(
                    f"[{target}] {provider.name} HTTP {exc.code}; "
                    f"failing over in {delay:.1f}s", flush=True
                )
                time.sleep(delay)

            except (URLError, TimeoutError, OSError, json.JSONDecodeError, TranslationError) as exc:
                last_error = exc
                provider.cooldown()
                delay = random.uniform(0.15, 0.8)
                print(
                    f"[{target}] {provider.name} unavailable: {exc}; "
                    f"failing over in {delay:.1f}s", flush=True
                )
                time.sleep(delay)

        raise TranslationError(
            f"{target}: free provider pool failed after {PROVIDER_MAX_ATTEMPTS} attempts: "
            f"{last_error}"
        )


def build_language(
    code: str,
    source: dict[str, str],
    cache_dir: Path,
    output_dir: Path,
    workers: int,
    translator: Translator,
):
    cache_file = cache_dir / f"{code}.json"
    cache = load_json(cache_file) if cache_file.exists() else {}
    if set(cache) - set(source):
        cache = {k: v for k, v in cache.items() if k in source}

    result = dict(cache)
    keys = list(source)
    missing = [(k, source[k]) for k in keys if not cache.get(k, "").strip()]

    print(f"\n=== [{code}] {len(keys)} strings | {workers} workers | missing {len(missing)} ===", flush=True)

    def one(item):
        key, value = item
        return key, translator.translate(value, code)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(one, item): item[0] for item in missing}
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            translated = future.result()
            result[key] = translated
            cache[key] = translated
            atomic_write_json(cache_file, cache)

            done = len(keys) - len(missing) + sum(
                1 for k in result if cache.get(k, "").strip()
            )
            # Avoid noisy logs while still showing progress.
            if len(result) % 25 == 0 or len(result) == len(keys):
                print(f"[{code}] {len(result)}/{len(keys)}", flush=True)

    missing_keys = [k for k in keys if not result.get(k, "").strip()]
    if missing_keys:
        raise TranslationError(
            f"{code}: refusing to publish incomplete pack; {len(missing_keys)} missing"
        )

    if set(result) != set(source):
        raise TranslationError(f"{code}: key-set validation failed")

    save_abl(output_dir / f"lang_{code}.abl", result)
    print(f"[{code}] DONE -> lang_{code}.abl | {len(result)} keys", flush=True)


def build_manifest(source: dict[str, str], output_dir: Path, version: str):
    packs = []
    for code in LANGUAGES:
        path = output_dir / f"lang_{code}.abl"
        if not path.exists():
            raise RuntimeError(f"manifest: missing completed pack {path}")
        packs.append({
            "language_code": code,
            "language": code,
            "direction": "rtl" if code in {"ar", "he", "fa", "ur"} else "ltr",
            "string_count": len(source),
            "size": path.stat().st_size,
            "sha256": sha256(path),
            "download_url": f"lang_{code}.abl",
        })

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
        build_language(code, source, cache_dir, output_dir, args.workers, translator)

    build_manifest(source, output_dir, args.version)
    print(f"All {len(LANGUAGES)} language packs completed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
