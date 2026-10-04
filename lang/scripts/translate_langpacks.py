#!/usr/bin/env python3
"""Translate the app's English strings into every downloadable language and
build the release assets the Abtin Maps app expects:

    out/lang_<code>.abl   gzip(UTF-8 JSON {key: translated string})
    out/manifest.json     {"languages": [{code, language, direction, ...}]}

Source of truth: source/en.json (copy of the app's assets/local/en.json,
key -> English string). Persian (fa) and English (en) are bundled in the
APK, so they are never generated here.

Engines
    google     free, no key (deep-translator); batched, backs off on rate limits
    auto       google, then Claude only for strings google could not do
    anthropic  better quality, needs ANTHROPIC_API_KEY (env)
    mock       offline test engine, returns "[code] text"

Human fixes: put corrected strings in overrides/<code>.json. They always win
and are never re-translated.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
import random
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# code -> (native name, direction). Mirrors _nativeLanguageNames in the app's
# language_pack_catalog.dart; fa/en are intentionally absent (bundled).
LANGUAGES: dict[str, tuple[str, str]] = {
    "ar": ("العربية", "rtl"), "cs": ("Čeština", "ltr"), "da": ("Dansk", "ltr"),
    "de": ("Deutsch", "ltr"), "el": ("Ελληνικά", "ltr"), "es": ("Español", "ltr"),
    "fi": ("Suomi", "ltr"), "fr": ("Français", "ltr"), "he": ("עברית", "rtl"),
    "hi": ("हिन्दी", "ltr"), "hu": ("Magyar", "ltr"), "id": ("Bahasa Indonesia", "ltr"),
    "it": ("Italiano", "ltr"), "ja": ("日本語", "ltr"), "ko": ("한국어", "ltr"),
    "nl": ("Nederlands", "ltr"), "no": ("Norsk", "ltr"), "pl": ("Polski", "ltr"),
    "pt": ("Português", "ltr"), "ro": ("Română", "ltr"), "ru": ("Русский", "ltr"),
    "sv": ("Svenska", "ltr"), "th": ("ไทย", "ltr"), "tr": ("Türkçe", "ltr"),
    "uk": ("Українська", "ltr"), "ur": ("اردو", "rtl"), "vi": ("Tiếng Việt", "ltr"),
    "zh": ("中文", "ltr"),
}
# Code the translation service uses when it differs from the app's code.
ENGINE_CODE = {"he": "iw", "no": "no", "zh": "zh-CN"}
ENGLISH_NAME = {
    "ar": "Arabic", "cs": "Czech", "da": "Danish", "de": "German", "el": "Greek",
    "es": "Spanish", "fi": "Finnish", "fr": "French", "he": "Hebrew", "hi": "Hindi",
    "hu": "Hungarian", "id": "Indonesian", "it": "Italian", "ja": "Japanese",
    "ko": "Korean", "nl": "Dutch", "no": "Norwegian (Bokmål)", "pl": "Polish",
    "pt": "Portuguese", "ro": "Romanian", "ru": "Russian", "sv": "Swedish",
    "th": "Thai", "tr": "Turkish", "uk": "Ukrainian", "ur": "Urdu",
    "vi": "Vietnamese", "zh": "Simplified Chinese",
}

# Never translated: brand/technical terms. Extend with glossary.json
# (a JSON list of extra strings).
DEFAULT_PROTECTED = ["Abtin Maps", "AbtinMaps", "Abtin", "GPS", "AQI", "POI", "HUD",
                     "OpenStreetMap", "GitHub", "Wi-Fi", "Bluetooth", "ABM", "ABV", "ABL"]

PLACEHOLDER_RE = re.compile(r"\{[^{}]*\}|%(?:\d+\$)?[sdif@]|\$\{?\w+\}?")
TOKEN_FMT = "\u27e6{}\u27e7"            # ⟦0⟧
TOKEN_RE = re.compile(r"\u27e6(\d+)\u27e7")


# ───────────────────────── protection of placeholders ─────────────────────────
class Style:
    """How placeholders are hidden from the engine. Engines sometimes mangle one
    style, so a failed string is retried with the next style."""
    def __init__(self, fmt: str, rx: str):
        self.fmt, self.rx = fmt, re.compile(rx)

    def tok(self, n: int) -> str:
        return self.fmt.format(n)


STYLES = [
    Style("\u27e6{}\u27e7", r"\u27e6\s*(\d+)\s*\u27e7"),   # ⟦0⟧
    Style("[[{}]]",         r"\[\[\s*(\d+)\s*\]\]"),         # [[0]]
    Style("<x{}>",          r"<\s*x\s*(\d+)\s*>"),           # <x0>
]


def protect(text: str, protected: list[str], style: Style) -> tuple[str, list[str]]:
    saved: list[str] = []

    def stash(m: re.Match) -> str:
        saved.append(m.group(0))
        return style.tok(len(saved) - 1)

    text = PLACEHOLDER_RE.sub(stash, text)
    if protected:
        terms = sorted(protected, key=len, reverse=True)
        pat = re.compile(r"(?<!\w)(?:" + "|".join(re.escape(t) for t in terms) + r")(?!\w)")
        text = pat.sub(stash, text)
    return text, saved


def restore(text: str, saved: list[str], style: Style) -> str | None:
    """Put originals back. None if any token was lost, duplicated or invented."""
    found = sorted(int(i) for i in style.rx.findall(text))
    if found != list(range(len(saved))):
        return None
    return style.rx.sub(lambda m: saved[int(m.group(1))], text)


def needs_translation(text: str) -> bool:
    """False for empty strings and strings with no letters (e.g. '%', '28°C')."""
    stripped = PLACEHOLDER_RE.sub("", text)
    return bool(re.search(r"[^\W\d_]", stripped))


# ───────────────────────────────── engines ──────────────────────────────────
class RateLimited(Exception):
    """The service keeps refusing us even after backing off."""


def _sleep(seconds: float) -> None:
    time.sleep(seconds * (0.75 + 0.5 * random.random()))      # jitter


class Engine:
    name = "?"
    max_chars = 3500          # per request (Google's web limit is 5000)
    pause = 1.0               # polite delay between requests

    def raw(self, text: str) -> str:
        raise NotImplementedError

    def translate_list(self, texts: list[str], out: list | None = None) -> list[str | None]:
        """One request per chunk of lines instead of one per string. If the
        engine changes the number of lines, the chunk is split in halves
        and retried, down to single strings. `out` is filled in place, so
        finished chunks are kept even if a later request is blocked."""
        if out is None:
            out = [None] * len(texts)
        chunks, cur, size = [], [], 0
        for i, t in enumerate(texts):
            if cur and size + len(t) + 1 > self.max_chars:
                chunks.append(cur); cur, size = [], 0
            cur.append(i); size += len(t) + 1
        if cur:
            chunks.append(cur)
        for idx in chunks:
            self._do(idx, texts, out)
        return out

    def _do(self, idx: list[int], texts: list[str], out: list) -> None:
        res = self.raw("\n".join(texts[i] for i in idx))
        _sleep(self.pause)
        lines = res.split("\n")
        if len(lines) == len(idx):
            for i, line in zip(idx, lines):
                out[i] = line
        elif len(idx) > 1:
            mid = len(idx) // 2
            self._do(idx[:mid], texts, out)
            self._do(idx[mid:], texts, out)
        # single string came back as several lines -> leave None (caller retries)


class GoogleEngine(Engine):
    name = "google"
    BACKOFF = (5, 20, 60, 120, 240)       # seconds, with jitter

    def __init__(self, code: str):
        try:
            from deep_translator import GoogleTranslator
        except ImportError:
            sys.exit("deep-translator is missing: pip install -r requirements.txt")
        self.tr = GoogleTranslator(source="en", target=ENGINE_CODE.get(code, code))

    def raw(self, text: str) -> str:
        last: Exception | None = None
        for wait in (0,) + self.BACKOFF:
            if wait:
                print(f"    ... rate-limited, waiting ~{wait}s", file=sys.stderr, flush=True)
                _sleep(wait)
            try:
                res = self.tr.translate(text)
                if res is not None:
                    return res
                last = RuntimeError("empty answer")
            except Exception as exc:                   # 429 / captcha / network
                last = exc
        raise RateLimited(str(last))


class AnthropicEngine(Engine):
    name = "anthropic"
    BATCH = 40

    def __init__(self, code: str):
        self.key = os.environ.get("ANTHROPIC_API_KEY")
        if not self.key:
            sys.exit("ANTHROPIC_API_KEY is not set")
        self.model = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
        self.lang = ENGLISH_NAME[code]
        self.pause = 0.5

    def _call(self, items: dict[str, str]) -> dict[str, str]:
        prompt = (
            f"Translate these navigation-app UI strings from English to {self.lang}. "
            "Keep every placeholder token (like \u27e60\u27e7, [[0]], <x0>) exactly as is - same "
            "number, same count. Keep the tone short and natural for a mobile UI. "
            "Reply with ONLY a JSON object with the same keys and translated values.\n\n"
            + json.dumps(items, ensure_ascii=False))
        body = json.dumps({"model": self.model, "max_tokens": 8000,
                           "messages": [{"role": "user", "content": prompt}]}).encode()
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages", data=body, method="POST",
            headers={"x-api-key": self.key, "anthropic-version": "2023-06-01",
                     "content-type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            text = "".join(b.get("text", "") for b in json.load(r)["content"])
        m = re.search(r"\{.*\}", text, re.S)
        return json.loads(m.group(0)) if m else {}

    def translate_list(self, texts: list[str], out: list | None = None) -> list[str | None]:
        if out is None:
            out = [None] * len(texts)
        for i in range(0, len(texts), self.BATCH):
            chunk = texts[i:i + self.BATCH]
            items = {str(n): t for n, t in enumerate(chunk)}
            for attempt in range(4):
                try:
                    got = self._call(items)
                    for n in range(len(chunk)):
                        if isinstance(got.get(str(n)), str):
                            out[i + n] = got[str(n)]
                    break
                except Exception as exc:
                    if attempt == 3:
                        raise RateLimited(str(exc))
                    _sleep(2 ** (attempt + 1))
            _sleep(self.pause)
        return out


class MockEngine(Engine):
    """Offline test engine. MOCK_MODE: ok | drop_a | merge_lines | block_after:N"""
    name = "mock"
    pause = 0.0

    def __init__(self, code: str):
        self.code, self.calls = code, 0
        self.mode = os.environ.get("MOCK_MODE", "ok")

    def raw(self, text: str) -> str:
        self.calls += 1
        if self.mode.startswith("block_after:") and self.calls > int(self.mode.split(":")[1]):
            raise RateLimited("mock block")
        if self.mode == "drop_a":
            text = STYLES[0].rx.sub("", text)
        if self.mode == "merge_lines" and "\n" in text:
            return " ".join(f"[{self.code}] {l}" for l in text.split("\n"))
        return "\n".join(f"[{self.code}] {l}" for l in text.split("\n"))


ENGINES = {"google": GoogleEngine, "anthropic": AnthropicEngine, "mock": MockEngine}


# ──────────────────────────────── translation ────────────────────────────────
def sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:16]


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def save_json_atomic(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def translate_language(code: str, source: dict[str, str], engine_name: str,
                       protected: list[str], cache_dir: Path, overrides_dir: Path,
                       force: bool, max_fallback_pct: float):
    """Returns (values | None, stats). None = pack must not be published
    (blocked by the service, or too many strings could not be translated)."""
    cache_path = cache_dir / f"{code}.json"
    cache = {} if force else load_json(cache_path)    # key -> {"src": hash, "text": str}
    overrides = load_json(overrides_dir / f"{code}.json")
    stats = {"overrides": 0, "cached": 0, "translated": 0, "kept_english": 0, "blocked": False}

    result: dict[str, str] = {}
    lines_of: dict[str, list[str]] = {}               # keys still to translate
    for key, en in source.items():
        if isinstance(overrides.get(key), str) and overrides[key].strip():
            result[key] = overrides[key]; stats["overrides"] += 1; continue
        if not needs_translation(en):
            result[key] = en; continue
        entry = cache.get(key)
        if isinstance(entry, dict) and entry.get("src") == sha1(en) and entry.get("text"):
            result[key] = entry["text"]; stats["cached"] += 1; continue
        lines_of[key] = en.split("\n")

    done: dict[tuple[str, int], str] = {}             # (key, line no) -> final text
    for key, lines in lines_of.items():
        for li, line in enumerate(lines):             # lines without letters stay as is
            if not needs_translation(line):
                done[(key, li)] = line

    def assemble_ready() -> None:
        """Move every fully translated key into result + cache (also on abort)."""
        for key, lines in lines_of.items():
            if key in result:
                continue
            if all((key, li) in done for li in range(len(lines))):
                final = "\n".join(done[(key, li)] for li in range(len(lines))).strip()
                if final:
                    result[key] = final
                    cache[key] = {"src": sha1(source[key]), "text": final}
                    stats["translated"] += 1
        save_json_atomic(cache_path, cache)

    def pending() -> list[tuple[str, int]]:
        return [(k, li) for k, ls in lines_of.items() for li in range(len(ls))
                if (k, li) not in done]

    def run_pass(engine: Engine, style: Style) -> None:
        todo = pending()
        if not todo:
            return
        prot = [protect(lines_of[k][li], protected, style) for k, li in todo]
        got: list = [None] * len(todo)
        try:
            engine.translate_list([p[0] for p in prot], got)
        finally:                                      # keep what finished before a block
            for (k, li), (_, saved), text in zip(todo, prot, got):
                if text is None:
                    continue
                back = restore(text, saved, style)
                if back is not None and back.strip():
                    done[(k, li)] = back.strip()

    try:
        if pending():
            primary = ENGINES["google" if engine_name == "auto" else engine_name](code)
            for style in STYLES:                      # retry mangled strings with another style
                run_pass(primary, style)
                assemble_ready()
                if not pending():
                    break
            if pending() and engine_name == "auto" and os.environ.get("ANTHROPIC_API_KEY"):
                print(f"    {len(pending())} string(s) left -> trying Claude", flush=True)
                fallback = AnthropicEngine(code)
                for style in STYLES[:2]:
                    run_pass(fallback, style)
                    assemble_ready()
                    if not pending():
                        break
    except RateLimited as exc:
        stats["blocked"] = True
        print(f"    ! service blocked us: {exc}", file=sys.stderr)
    finally:
        assemble_ready()                              # progress is kept for the next run

    for key in lines_of:
        if key not in result:
            result[key] = source[key]                 # safe fallback: English
            stats["kept_english"] += 1

    total = max(1, len(source))
    too_many = stats["kept_english"] * 100.0 / total > max_fallback_pct
    if stats["blocked"] or too_many:
        return None, stats
    return dict(sorted(result.items())), stats


# ───────────────────────────────── packaging ─────────────────────────────────
def write_abl(path: Path, values: dict[str, str]) -> None:
    raw = json.dumps(values, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":")).encode("utf-8")
    with open(path, "wb") as f:                # mtime=0 → byte-identical rebuilds
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0, compresslevel=9) as gz:
            gz.write(raw)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", type=Path, default=ROOT / "source/en.json")
    ap.add_argument("--out", type=Path, default=ROOT / "out")
    ap.add_argument("--languages", default="all",
                    help="comma list of codes, or 'all' (default)")
    ap.add_argument("--engine", choices=sorted(ENGINES) + ["auto"], default="google",
                    help="auto = google, and Claude for what google could not do "
                         "(needs ANTHROPIC_API_KEY)")
    ap.add_argument("--cache-dir", type=Path, default=ROOT / ".l10n_cache")
    ap.add_argument("--overrides-dir", type=Path, default=ROOT / "overrides")
    ap.add_argument("--glossary", type=Path, default=ROOT / "glossary.json")
    ap.add_argument("--force", action="store_true", help="ignore cache, retranslate all")
    ap.add_argument("--max-fallback-pct", type=float, default=3.0,
                    help="a pack is skipped if more than this %% of strings could "
                         "not be translated (the previous release pack stays)")
    args = ap.parse_args()

    source = {k: v for k, v in load_json(args.source).items() if isinstance(v, str)}
    if len(source) < 50:
        sys.exit(f"source looks wrong ({len(source)} keys): {args.source}")

    codes = list(LANGUAGES) if args.languages == "all" else \
        [c.strip().lower() for c in args.languages.split(",") if c.strip()]
    bad = [c for c in codes if c not in LANGUAGES]
    if bad:
        sys.exit(f"unknown/bundled language(s): {', '.join(bad)} (fa/en are not generated)")

    extra = json.loads(args.glossary.read_text(encoding="utf-8")) if args.glossary.exists() else []
    protected = DEFAULT_PROTECTED + [str(x) for x in extra]

    args.out.mkdir(parents=True, exist_ok=True)
    version = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d") + "-" + \
        sha1(json.dumps(source, sort_keys=True, ensure_ascii=False))[:8]
    entries, failed, blocked_in_row = [], [], 0
    for code in codes:
        print(f"[{code}] {LANGUAGES[code][0]}", flush=True)
        values, st = translate_language(code, source, args.engine, protected,
                                        args.cache_dir, args.overrides_dir, args.force,
                                        args.max_fallback_pct)
        print(f"    {st}", flush=True)
        if values is None:
            failed.append(code)
            print(f"    ! [{code}] not published (progress is cached; run again)", file=sys.stderr)
            blocked_in_row = blocked_in_row + 1 if st["blocked"] else 0
            if blocked_in_row >= 3:
                print("! 3 languages in a row were blocked - stopping. Wait and run again.",
                      file=sys.stderr)
                break
            if st["blocked"]:
                time.sleep(60)                        # cool down before the next language
            continue
        blocked_in_row = 0
        abl = args.out / f"lang_{code}.abl"
        write_abl(abl, values)
        entries.append({
            "code": code, "language": LANGUAGES[code][0],
            "direction": LANGUAGES[code][1], "string_count": len(values),
            "size": abl.stat().st_size, "sha256": sha256_file(abl),
            "version": version, "download_url": abl.name,
        })

    # A partial run (--languages fa,tr) must not drop the other languages from
    # the manifest: merge with the manifest that is already in out/.
    mpath = args.out / "manifest.json"
    old = {e["code"]: e for e in load_json(mpath).get("languages", []) if isinstance(e, dict)}
    old.update({e["code"]: e for e in entries})
    manifest = {"schema_version": 1, "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "source_keys": len(source), "engine": args.engine,
                "languages": [old[c] for c in sorted(old)]}
    mpath.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"done: {len(entries)} pack(s) built, manifest has {len(manifest['languages'])} languages")
    if failed:
        print(f"NOT built: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
