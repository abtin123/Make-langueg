#!/usr/bin/env python3
"""Translate the app's English strings into every downloadable language and
build the release assets the Abtin Maps app expects:

    out/lang_<code>.abl   gzip(UTF-8 JSON {key: translated string})
    out/manifest.json     {"languages": [{code, language, direction, ...}]}

Source of truth: source/en.json (copy of the app's assets/local/en.json,
key -> English string). Persian (fa) and English (en) are bundled in the
APK, so they are never generated here.

Engines
    google     free, no key (deep-translator)
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
def protect(text: str, protected: list[str]) -> tuple[str, list[str]]:
    """Replace placeholders/brand terms with ⟦n⟧ tokens."""
    saved: list[str] = []

    def stash(m: re.Match) -> str:
        saved.append(m.group(0))
        return TOKEN_FMT.format(len(saved) - 1)

    text = PLACEHOLDER_RE.sub(stash, text)
    if protected:
        terms = sorted(protected, key=len, reverse=True)
        pat = re.compile(r"(?<!\w)(?:" + "|".join(re.escape(t) for t in terms) + r")(?!\w)")
        text = pat.sub(stash, text)
    return text, saved


def restore(text: str, saved: list[str]) -> str | None:
    """Put originals back. Returns None if any token was lost or invented."""
    # Engines sometimes add spaces inside the brackets: "⟦ 0 ⟧".
    text = re.sub(r"\u27e6\s*(\d+)\s*\u27e7", lambda m: TOKEN_FMT.format(m.group(1)), text)
    found = [int(i) for i in TOKEN_RE.findall(text)]
    if sorted(found) != list(range(len(saved))):
        return None
    return TOKEN_RE.sub(lambda m: saved[int(m.group(1))], text)


def needs_translation(text: str) -> bool:
    """False for empty strings and strings with no letters (e.g. '%', '28°C')."""
    stripped = PLACEHOLDER_RE.sub("", text)
    return bool(re.search(r"[^\W\d_]", stripped))


# ───────────────────────────────── engines ──────────────────────────────────
class MockEngine:
    name = "mock"

    def __init__(self, code: str):
        self.code = code

    def translate_many(self, texts: list[str]) -> list[str]:
        return [f"[{self.code}] {t}" for t in texts]


class GoogleEngine:
    name = "google"

    def __init__(self, code: str):
        try:
            from deep_translator import GoogleTranslator
        except ImportError:
            sys.exit("deep-translator is missing: pip install -r requirements.txt")
        self.tr = GoogleTranslator(source="en", target=ENGINE_CODE.get(code, code))

    def translate_many(self, texts: list[str]) -> list[str]:
        out = []
        for t in texts:
            for attempt in range(4):
                try:
                    out.append(self.tr.translate(t) or t)
                    break
                except Exception as exc:  # network / rate limit
                    if attempt == 3:
                        print(f"    ! translate failed, keeping English: {exc}", file=sys.stderr)
                        out.append(t)
                    else:
                        time.sleep(2 ** attempt)
            time.sleep(0.05)
        return out


class AnthropicEngine:
    name = "anthropic"
    BATCH = 40

    def __init__(self, code: str):
        self.key = os.environ.get("ANTHROPIC_API_KEY")
        if not self.key:
            sys.exit("ANTHROPIC_API_KEY is not set")
        self.model = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
        self.lang = ENGLISH_NAME[code]

    def _call(self, items: dict[str, str]) -> dict[str, str]:
        prompt = (
            f"Translate these navigation-app UI strings from English to {self.lang}. "
            "Keep every ⟦n⟧ token exactly as is (same number, same count). "
            "Keep the tone short and natural for a mobile UI; keep line breaks. "
            "Reply with ONLY a JSON object with the same keys and translated values.\n\n"
            + json.dumps(items, ensure_ascii=False)
        )
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

    def translate_many(self, texts: list[str]) -> list[str]:
        out: list[str] = []
        for i in range(0, len(texts), self.BATCH):
            chunk = texts[i:i + self.BATCH]
            items = {str(n): t for n, t in enumerate(chunk)}
            got: dict[str, str] = {}
            for attempt in range(3):
                try:
                    got = self._call(items)
                    break
                except Exception as exc:
                    if attempt == 2:
                        print(f"    ! API failed, keeping English: {exc}", file=sys.stderr)
                    else:
                        time.sleep(2 ** attempt)
            out.extend(str(got.get(str(n), t)) for n, t in enumerate(chunk))
        return out


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


def translate_language(code: str, source: dict[str, str], engine_name: str,
                       protected: list[str], cache_dir: Path, overrides_dir: Path,
                       force: bool) -> tuple[dict[str, str], dict]:
    cache_path = cache_dir / f"{code}.json"
    cache = {} if force else load_json(cache_path)   # key -> {"src": hash, "text": str}
    overrides = load_json(overrides_dir / f"{code}.json")
    stats = {"overrides": 0, "cached": 0, "translated": 0, "kept_english": 0}

    result: dict[str, str] = {}
    todo: list = []   # (key, line parts)

    for key, en in source.items():
        if isinstance(overrides.get(key), str) and overrides[key].strip():
            result[key] = overrides[key]; stats["overrides"] += 1; continue
        if not needs_translation(en):
            result[key] = en; continue
        entry = cache.get(key)
        if isinstance(entry, dict) and entry.get("src") == sha1(en) and entry.get("text"):
            result[key] = entry["text"]; stats["cached"] += 1; continue
        # translate line by line so "\n" survives
        parts = []   # (protected text, saved originals, needs engine?)
        for line in en.split("\n"):
            prot, saved = protect(line, protected)
            parts.append((prot, saved, needs_translation(line)))
        todo.append((key, parts))

    if todo:
        engine = ENGINES[engine_name](code)
        flat = [(ki, li) for ki, (_, parts) in enumerate(todo)
                for li, part in enumerate(parts) if part[2]]
        texts = [todo[ki][1][li][0] for ki, li in flat]
        translated = engine.translate_many(texts) if texts else []
        by_pos = dict(zip(flat, translated))

        for ki, (key, parts) in enumerate(todo):
            en = source[key]
            lines, ok = [], True
            for li, (prot, saved, send) in enumerate(parts):
                back = restore(by_pos[(ki, li)] if send else prot, saved)
                if back is None:               # placeholder damaged -> unsafe
                    ok = False; break
                lines.append(back)
            final = "\n".join(lines).strip() if ok else ""
            if final:
                result[key] = final
                cache[key] = {"src": sha1(en), "text": final}
                stats["translated"] += 1
            else:
                result[key] = en               # safe fallback: English
                stats["kept_english"] += 1

    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, ensure_ascii=False, sort_keys=True) + "\n",
                          encoding="utf-8")
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
    ap.add_argument("--engine", choices=sorted(ENGINES), default="google")
    ap.add_argument("--cache-dir", type=Path, default=ROOT / ".l10n_cache")
    ap.add_argument("--overrides-dir", type=Path, default=ROOT / "overrides")
    ap.add_argument("--glossary", type=Path, default=ROOT / "glossary.json")
    ap.add_argument("--force", action="store_true", help="ignore cache, retranslate all")
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
    entries = []
    for code in codes:
        print(f"[{code}] {LANGUAGES[code][0]}", flush=True)
        values, st = translate_language(code, source, args.engine, protected,
                                        args.cache_dir, args.overrides_dir, args.force)
        print(f"    {st}", flush=True)
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
    print(f"done: {len(entries)} pack(s), manifest has {len(manifest['languages'])} languages")


if __name__ == "__main__":
    main()
