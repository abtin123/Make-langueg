#!/usr/bin/env python3
"""Build the 28 downloadable AbtinMaps language packs.

Pipeline:
  1. Extract the Persian ("fa") base-key table straight out of
     lib/core/localization/app_localizations.dart — that Dart map is the
     single source of truth for every string in the app.
  2. Also refresh assets/local/fa.json and assets/local/en.json so the two
     bundled locales stay in sync with the Dart source.
  3. Translate every fa string into each of the 28 target languages using a
     pool of free/public machine-translation engines (Google's public GTX
     endpoint, MyMemory, several public Lingva instances, and optionally a
     public/local Argos Translate instance), with automatic failover,
     placeholder protection (so {name}, %s, <b> etc. survive translation),
     and a persistent on-disk cache so re-runs only translate what's still
     missing.
  4. Gzip-pack each completed language into tool/l10n/out/lang_<code>.abl
     and write tool/l10n/out/manifest.json.

Run from the project root:
    python tool/l10n/build_release.py

Everything in tool/l10n/out/ is what gets attached to the GitHub
"langpacks-latest" release (see .github/workflows/translations.yml).
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
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DART_SOURCE = ROOT / "lib/core/localization/app_localizations.dart"
ASSETS_LOCAL = ROOT / "assets/local"

# The 28 downloadable languages (fa and en ship inside the APK and are
# never part of a downloadable pack). Keep this in sync with
# assets/local/generate_locales.py.
LANGUAGES = [
    "ar", "cs", "da", "de", "el", "es", "fi", "fr",
    "he", "hi", "hu", "id", "it", "ja", "ko", "nl", "no", "pl",
    "pt", "ro", "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

RTL_LANGUAGES = {"ar", "he", "fa", "ur"}

# Some free engines expect a different code than the one the app itself
# uses internally. Only the outgoing translation request is affected —
# the pack is still written out as lang_<app_code>.abl.
REQUEST_CODE_OVERRIDES = {
    "zh": "zh-CN",
}

DEFAULT_WORKERS = max(1, int(os.getenv("TRANSLATION_WORKERS", "12")))
REQUEST_TIMEOUT = float(os.getenv("TRANSLATION_TIMEOUT", "25"))
PROVIDER_MAX_ATTEMPTS = max(1, int(os.getenv("PROVIDER_MAX_ATTEMPTS", "3")))
PROVIDER_COOLDOWN = float(os.getenv("PROVIDER_COOLDOWN", "20"))
PROVIDER_INTERVAL = float(os.getenv("PROVIDER_INTERVAL", "0.20"))
LANGUAGE_PASSES = max(1, int(os.getenv("LANGUAGE_PASSES", "3")))
PASS_MAX_FAILURES = max(1, int(os.getenv("PASS_MAX_FAILURES", "40")))
CACHE_FLUSH_EVERY = 25

FREE_PROVIDERS = [
    x.strip().lower()
    for x in os.getenv(
        "FREE_TRANSLATION_PROVIDERS", "google,mymemory,lingva"
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
        "ARGOS_ENDPOINTS", "https://translate.argosopentech.com"
    ).split(";") if x.strip()
]

USE_LOCAL_ARGOS = os.getenv("ARGOS_LOCAL", "0").lower() in {"1", "true", "yes"}


class TranslationError(RuntimeError):
    pass


# --------------------------------------------------------------------------
# Step 1: extraction straight from the Dart source (source of truth)
# --------------------------------------------------------------------------

PAIR_PATTERNS = (
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", re.S),
    re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*\"((?:\\.|[^\"\\])*)\"", re.S),
    re.compile(r'"((?:\\.|[^"\\])*)"\s*:\s*\'((?:\\.|[^\'\\])*)\'', re.S),
    re.compile(r'"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"', re.S),
)


def unescape(value: str) -> str:
    return (
        value.replace(r"\\", "\\")
        .replace(r"\'", "'")
        .replace(r"\"", '"')
        .replace(r"\n", "\n")
        .replace(r"\r", "\r")
        .replace(r"\t", "\t")
    )


def extract_block(source: str, language: str) -> str:
    marker = f"    '{language}': {{"
    start = source.index(marker) + len(marker)
    if language == "fa":
        end = source.index("    'en': {", start)
    else:
        end = source.index("\n  };", start)
    return source[start:end]


def extract(source: str, language: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for pattern in PAIR_PATTERNS:
        for match in pattern.finditer(extract_block(source, language)):
            key, value = map(unescape, match.groups())
            values[key] = value
    return dict(sorted(values.items()))


def refresh_bundled_json(fa: dict[str, str], en: dict[str, str]) -> None:
    """Keep assets/local/fa.json and assets/local/en.json in sync with Dart."""
    ASSETS_LOCAL.mkdir(parents=True, exist_ok=True)
    for code, data in (("fa", fa), ("en", en)):
        path = ASSETS_LOCAL / f"{code}.json"
        path.write_text(
            json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


# --------------------------------------------------------------------------
# Step 2: gzip pack I/O
# --------------------------------------------------------------------------

def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def save_abl(path: Path, data: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.open(tmp, "wb", compresslevel=9) as f:
        f.write(raw)
    os.replace(tmp, path)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------
# Step 3: placeholder protection so {name}/%s/<b>/${x} survive translation
# --------------------------------------------------------------------------

def protect(text: str) -> tuple[str, dict[str, str]]:
    tokens: dict[str, str] = {}
    patterns = [
        r"\{\{[^{}]+\}\}", r"\{[^{}]+\}", r"%\d+\$?[sdif]",
        r"%[sdif]", r"\$\{[^}]+\}", r"<[^>]+>",
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


_TOKEN_RE = re.compile(r"(?:_+\s*)?ABTIN[\s_]*TOKEN[\s_]*(\d+)(?:\s*_+)?", re.IGNORECASE)
_LEFTOVER_RE = re.compile(r"abtin[\s_]*token", re.IGNORECASE)
_BAD_MARKERS = (
    "mymemory warning", "invalid target language",
    "please select two distinct languages", "query length limit exceeded",
)


def restore(text: str, tokens: dict[str, str]) -> str:
    def sub(m: re.Match) -> str:
        return tokens.get(f"__ABTIN_TOKEN_{int(m.group(1))}__", m.group(0))
    return _TOKEN_RE.sub(sub, text)


def validate_restored(source: str, translated: str) -> bool:
    _, src_tokens = protect(source)
    _, dst_tokens = protect(translated)
    return sorted(src_tokens.values()) == sorted(dst_tokens.values())


def is_bad_translation(source: str, translated: str) -> bool:
    if not translated or not translated.strip():
        return True
    if _LEFTOVER_RE.search(translated):
        return True
    low = translated.lower()
    if any(m in low for m in _BAD_MARKERS):
        return True
    return not validate_restored(source, translated)


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


# --------------------------------------------------------------------------
# Step 4: free/public translation providers with failover
# --------------------------------------------------------------------------

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


def _req_target(target: str) -> str:
    return REQUEST_CODE_OVERRIDES.get(target, target)


class Provider:
    def __init__(self, name: str, kind: str, endpoint: str = "", translations: dict[str, Any] | None = None):
        self.name = name
        self.kind = kind
        self.endpoint = endpoint.rstrip("/")
        self.translations = translations
        self.rate_limiter = RateLimiter(PROVIDER_INTERVAL)
        self._cooldown_until = 0.0
        self._cooldown_lock = threading.Lock()

    def cooldown(self, seconds: float = PROVIDER_COOLDOWN):
        with self._cooldown_lock:
            self._cooldown_until = max(self._cooldown_until, time.monotonic() + seconds)

    def available(self) -> bool:
        with self._cooldown_lock:
            return time.monotonic() >= self._cooldown_until

    def supports(self, target: str) -> bool:
        return self.translations is None or target in self.translations

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
        if is_bad_translation(source, translated):
            raise TranslationError(f"{self.name}: rejected translation")
        return translated

    def translate_google(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        url = (
            "https://translate.googleapis.com/translate_a/single"
            f"?client=gtx&sl=fa&tl={quote(_req_target(target))}&dt=t&q={quote(protected)}"
        )
        req = Request(url, headers={"User-Agent": "AbtinMaps-LanguageBuilder/6.0", "Accept": "application/json"})
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            translated = parse_gtx_response(json.loads(response.read()))
        return self._validate(text, translated, tokens)

    def translate_mymemory(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        if len(protected.encode("utf-8")) > 450:
            raise TranslationError(f"{self.name}: segment too large")
        self.rate_limiter.wait()
        url = (
            "https://api.mymemory.translated.net/get"
            f"?q={quote(protected)}&langpair=fa%7C{quote(_req_target(target))}&mt=1"
        )
        req = Request(url, headers={"User-Agent": "AbtinMaps-LanguageBuilder/6.0", "Accept": "application/json"})
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        try:
            status = int(payload.get("responseStatus", 200))
        except (TypeError, ValueError):
            status = 0
        if status != 200:
            raise TranslationError(f"{self.name}: status {status}")
        translated = (payload.get("responseData") or {}).get("translatedText") or ""
        return self._validate(text, translated, tokens)

    def translate_lingva(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        url = f"{self.endpoint}/api/v1/fa/{quote(_req_target(target))}/{quote(protected, safe='')}"
        req = Request(url, headers={"User-Agent": "AbtinMaps-LanguageBuilder/6.0", "Accept": "application/json"})
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translation", "")
        return self._validate(text, translated, tokens)

    def translate_argos(self, text: str, target: str) -> str:
        protected, tokens = protect(text)
        self.rate_limiter.wait()
        body = json.dumps({"q": protected, "source": "fa", "target": _req_target(target), "format": "text"}, ensure_ascii=False).encode("utf-8")
        req = Request(
            f"{self.endpoint}/translate", data=body,
            headers={"User-Agent": "AbtinMaps-LanguageBuilder/6.0", "Accept": "application/json", "Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            payload = json.loads(response.read())
        translated = payload.get("translatedText", "")
        return self._validate(text, translated, tokens)

    def translate_local_argos(self, text: str, target: str) -> str:
        translation = (self.translations or {}).get(target)
        if translation is None:
            raise TranslationError(f"{self.name}: no fa->{target} model installed")
        protected, tokens = protect(text)
        with _ARGOS_RUN_LOCK:
            translated = translation.translate(protected)
        return self._validate(text, translated, tokens)


_ARGOS_RUN_LOCK = threading.Lock()


def load_local_argos() -> dict[str, Any]:
    try:
        import argostranslate.translate as at
        langs = at.get_installed_languages()
        src = next((l for l in langs if l.code == "fa"), None)
        if src is None:
            return {}
        found: dict[str, Any] = {}
        for lang in langs:
            if lang.code == "fa":
                continue
            translation = src.get_translation(lang)
            if translation is not None:
                found[lang.code] = translation
        return found
    except Exception as exc:
        print(f"Local Argos disabled: {exc}", flush=True)
        return {}


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
            local = load_local_argos()
            if local:
                self.providers.append(Provider("argos-local", "local_argos", translations=local))
        if not self.providers:
            raise RuntimeError("No free translation providers configured")
        self._lock = threading.Lock()
        self._cursor = 0

    def next_provider(self, attempted: set[str], target: str) -> Provider | None:
        with self._lock:
            n = len(self.providers)
            for _ in range(n):
                p = self.providers[self._cursor % n]
                self._cursor += 1
                if p.name not in attempted and p.supports(target) and p.available():
                    return p
            for p in self.providers:
                if p.name not in attempted and p.supports(target):
                    return p
        return None

    def summary(self) -> str:
        return ", ".join(p.name for p in self.providers)


class Translator:
    def __init__(self):
        self.pool = ProviderPool()

    def translate(self, text: str, target: str) -> str:
        if not text.strip():
            return text
        last_error: Exception | None = None
        attempted: set[str] = set()
        for _ in range(max(PROVIDER_MAX_ATTEMPTS, 6)):
            provider = self.pool.next_provider(attempted, target)
            if provider is None:
                break
            attempted.add(provider.name)
            try:
                translated = provider.translate(text, target)
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
                time.sleep(delay + random.uniform(0.0, 0.5))
            except Exception as exc:
                last_error = exc
                provider.cooldown()
                time.sleep(random.uniform(0.15, 0.8))
        raise TranslationError(f"{target}: provider pool failed after {len(attempted)} attempts: {last_error}")


# --------------------------------------------------------------------------
# Step 5: build each language pack
# --------------------------------------------------------------------------

def build_language(code: str, source: dict[str, str], cache_dir: Path, output_dir: Path, workers: int, translator: Translator) -> bool:
    cache_file = cache_dir / f"{code}.json"
    try:
        cache = json.loads(cache_file.read_text(encoding="utf-8")) if cache_file.exists() else {}
    except (OSError, ValueError):
        cache = {}
    cache = {k: v for k, v in cache.items() if k in source and not is_bad_translation(source[k], v)}

    keys = list(source)

    def pending() -> list[tuple[str, str]]:
        return [(k, source[k]) for k in keys if source[k].strip() and not cache.get(k, "").strip()]

    def one(item: tuple[str, str]) -> str:
        return translator.translate(item[1], code)

    last_error: Exception | None = None
    for attempt in range(1, LANGUAGE_PASSES + 1):
        missing = pending()
        if not missing:
            break
        if attempt > 1:
            time.sleep(min(30, 5 * attempt))
        print(f"=== [{code}] pass {attempt}/{LANGUAGE_PASSES} | missing {len(missing)}/{len(keys)} ===", flush=True)

        failures = 0
        done = 0
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=workers)
        try:
            futures = {pool.submit(one, item): item[0] for item in missing}
            for future in concurrent.futures.as_completed(futures):
                key = futures[future]
                try:
                    cache[key] = future.result()
                except concurrent.futures.CancelledError:
                    continue
                except Exception as exc:
                    last_error = exc
                    failures += 1
                    if failures >= PASS_MAX_FAILURES:
                        print(f"[{code}] too many failures this pass; pausing", flush=True)
                        break
                    continue
                done += 1
                if done % CACHE_FLUSH_EVERY == 0:
                    atomic_write_json(cache_file, cache)
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
            atomic_write_json(cache_file, cache)

    result = {
        k: (cache[k] if cache.get(k, "").strip() else (source[k] if not source[k].strip() else ""))
        for k in keys
    }
    missing_keys = [k for k in keys if source[k].strip() and not result[k].strip()]
    if missing_keys:
        print(f"[{code}] INCOMPLETE: {len(missing_keys)} keys still missing (last error: {last_error})", flush=True)
        return False

    save_abl(output_dir / f"lang_{code}.abl", result)
    print(f"[{code}] DONE -> lang_{code}.abl | {len(result)} keys", flush=True)
    return True


def build_manifest(source: dict[str, str], output_dir: Path, completed: list[str], version: str) -> None:
    packs = []
    for code in completed:
        path = output_dir / f"lang_{code}.abl"
        packs.append({
            "language_code": code,
            "direction": "rtl" if code in RTL_LANGUAGES else "ltr",
            "string_count": len(source),
            "size": path.stat().st_size,
            "sha256": sha256(path),
            "download_url": f"lang_{code}.abl",
        })
    manifest = {"version": version, "source_language": "fa", "key_count": len(source), "languages": packs}
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(ROOT / "tool/l10n/out"))
    parser.add_argument("--cache", default=str(ROOT / "tool/l10n/.translation_cache"))
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    parser.add_argument("--version", default=os.getenv("LANGPACK_VERSION", "1"))
    parser.add_argument("--dry-run", action="store_true", help="Skip network calls; just verify extraction/packaging.")
    args = parser.parse_args()

    text = DART_SOURCE.read_text(encoding="utf-8")
    fa = extract(text, "fa")
    en = extract(text, "en")
    if len(fa) < 100 or set(fa) != set(en):
        raise SystemExit(f"Localization extraction failed: fa={len(fa)}, en={len(en)}")
    refresh_bundled_json(fa, en)
    print(f"Source: {DART_SOURCE} | keys: {len(fa)}", flush=True)
    print(f"Targets: {len(LANGUAGES)} | workers: {args.workers}", flush=True)

    output_dir = Path(args.output)
    cache_dir = Path(args.cache)
    output_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        for code in LANGUAGES:
            save_abl(output_dir / f"lang_{code}.abl", {k: f"[{code}] {v}" for k, v in fa.items()})
        build_manifest(fa, output_dir, LANGUAGES, args.version)
        print("Dry run complete (no network calls made).", flush=True)
        return 0

    translator = Translator()
    print(f"Provider pool: {translator.pool.summary()}", flush=True)

    completed: list[str] = []
    failed: list[str] = []
    for code in LANGUAGES:
        try:
            if build_language(code, fa, cache_dir, output_dir, args.workers, translator):
                completed.append(code)
            else:
                failed.append(code)
        except Exception as exc:
            failed.append(code)
            print(f"[{code}] FAILED: {exc}", flush=True)

    if completed:
        build_manifest(fa, output_dir, completed, args.version)

    if failed:
        print(f"Incomplete languages: {', '.join(failed)}. Progress is cached; re-run to resume.", flush=True)
        return 1

    print(f"All {len(LANGUAGES)} language packs completed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
