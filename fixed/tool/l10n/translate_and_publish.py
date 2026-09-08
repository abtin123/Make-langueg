#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AbtinMaps — ترجمهٔ خودکار کل رابط کاربری اپ و انتشار بسته‌های زبان روی گیت‌هاب

این اسکریپت همهٔ متن‌های رابط کاربری اپ را به زبان‌های مختلف ترجمه می‌کند و
بسته‌های زبان (فایل‌های .abl) را می‌سازد و روی گیت‌هاب منتشر می‌کند تا هر کسی
بتواند زبان دلخواهش را دانلود کند.

مراحل:
  1) استخراج همهٔ کلیدهای UI از lib/core/localization/app_localizations.dart
     (فارسی منبع اصلی، انگلیسی fallback است).
  2) برای هر زبان، ترجمهٔ خودکارِ کلیدهایِ ترجمه‌نشده (جای‌نگهدارهایی مثل
     {name} محافظت می‌شوند تا خراب نشوند). ترجمه‌های موجود دست‌نخورده می‌مانند.
  3) نوشتن assets/local/<code>.json برای هر زبان.
  4) ساخت بسته‌های .abl (gzip) + manifest.json در پوشهٔ out/.
  5) (اختیاری) commit و push روی گیت‌هاب و انتشار/به‌روزرسانی release با تگ
     langpacks-latest — اپ مانیفست را از همان‌جا می‌خواند و هر زبانی را دانلود می‌کند.

چیزی که عمداً ترجمه نمی‌شود:
  * خودِ نقشه. برچسب‌های نقشه از دادهٔ محلی نقشه می‌آیند (نقشهٔ ایران فارسی
    می‌ماند، نقشهٔ ترکیه ترکی می‌ماند، ...). این اسکریپت فقط متن‌های UI را
    لمس می‌کند، نه دادهٔ نقشه را.
  * هیچ فونت پرچمی اضافه نمی‌شود. پرچم‌ها از assetهای SVG خودِ اپ
    (assets/images/flags/*.svg) توسط FlagAvatar + locale_flags.dart رندر
    می‌شوند — برای هر زبان یک پرچم واقعی داخل خودِ APK هست.

استفاده:
  python tool/l10n/translate_and_publish.py                 # ترجمه + ساخت + انتشار
  python tool/l10n/translate_and_publish.py --no-publish   # فقط ترجمه + ساخت
  python tool/l10n/translate_and_publish.py --build-only   # ساخت بسته‌ها از JSONهای موجود
  python tool/l10n/translate_and_publish.py --offline      # بدون اینترنت: جاهای خالی با انگلیسی
  python tool/l10n/translate_and_publish.py --langs tr,de --dry-run
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "lib/core/localization/app_localizations.dart"
LOCAL = ROOT / "assets/local"
OUT = ROOT / "out"
FLAGS_DIR = ROOT / "assets/images/flags"

# همهٔ زبان‌هایی که اپ به‌صورت بستهٔ قابل‌دانلود عرضه می‌کند.
LANGUAGES = [
    "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fr",
    "he", "hi", "hu", "id", "it", "ja", "ko", "nl", "no", "pl",
    "pt", "ro", "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

# نام بومی هر زبان (در مانیفست می‌رود تا در فهرست اپ با نام خودش دیده شود).
NATIVE_NAMES = {
    "ar": "العربية", "cs": "Čeština", "da": "Dansk", "de": "Deutsch",
    "el": "Ελληνικά", "en": "English", "es": "Español", "fa": "فارسی",
    "fi": "Suomi", "fr": "Français", "he": "עברית", "hi": "हिन्दी",
    "hu": "Magyar", "id": "Bahasa Indonesia", "it": "Italiano",
    "ja": "日本語", "ko": "한국어", "nl": "Nederlands", "no": "Norsk",
    "pl": "Polski", "pt": "Português", "ro": "Română", "ru": "Русский",
    "sv": "Svenska", "th": "ไทย", "tr": "Türkçe", "uk": "Українська",
    "ur": "اردو", "vi": "Tiếng Việt", "zh": "中文",
}

# زبان‌های راست‌به‌چپ (اپ `direction` را از مانیفست می‌خواند).
RTL = {"fa", "ar", "he", "ur"}

# زبان -> کشورِ پرچمی که داخل اپ باندل شده (همان locale_flags.dart).
LANGUAGE_FLAG_COUNTRY = {
    "fa": "ir", "en": "gb", "ar": "sa", "tr": "tr", "ur": "pk",
    "ru": "ru", "fr": "fr", "de": "de", "es": "es", "it": "it",
    "zh": "cn", "hi": "in", "cs": "cz", "da": "dk", "el": "gr",
    "fi": "fi", "he": "il", "hu": "hu", "id": "id", "ja": "jp",
    "ko": "kr", "nl": "nl", "no": "no", "pl": "pl", "pt": "pt",
    "ro": "ro", "sv": "se", "th": "th", "uk": "ua", "vi": "vn",
}

_PLACEHOLDER = re.compile(r"\{[a-z_][a-z0-9_]*\}")
_TOKEN_RE = re.compile("\uE000(\\d+)\uE001")

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
        .replace(r'\"', '"')
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
            if key in values and values[key] != value:
                raise ValueError(f"کلید تکراری متناقض: {key}")
            values[key] = value
    return dict(sorted(values.items()))


def protect_placeholders(text: str) -> tuple[str, list[str]]:
    parts: list[str] = []

    def repl(m: re.Match) -> str:
        parts.append(m.group(0))
        return f"\uE000{len(parts) - 1}\uE001"

    return _PLACEHOLDER.sub(repl, text), parts


def restore_placeholders(text: str, parts: list[str]) -> str:
    def repl(m: re.Match) -> str:
        idx = int(m.group(1))
        return parts[idx] if idx < len(parts) else m.group(0)

    return _TOKEN_RE.sub(repl, text)


def http_get_json(url: str, params: dict):
    try:
        import requests  # type: ignore

        r = requests.get(url, params=params, timeout=25)
        r.raise_for_status()
        return r.json()
    except Exception:
        import urllib.parse
        import urllib.request

        qs = urllib.parse.urlencode(params)
        req = urllib.request.Request(
            f"{url}?{qs}", headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            return json.loads(resp.read().decode("utf-8"))


def google_translate_batch(texts: list[str], target: str) -> list[str]:
    """ترجمهٔ دسته‌ای از فارسی به `target` با endpoint رایگان گوگل."""
    if not texts:
        return []
    query = "\n".join(texts)
    url = "https://translate.googleapis.com/translate_a/single"
    data = http_get_json(
        url, {"client": "gtx", "sl": "fa", "tl": target, "dt": "t", "q": query}
    )
    translated = "".join(seg[0] for seg in data[0] if seg and seg[0])
    lines = translated.split("\n")
    if len(lines) == len(texts):
        return lines
    # در صورت ناهماهنگی، تک‌تک ترجمه کن
    return [google_translate_batch([t], target)[0] for t in texts]


def mymemory_translate(text: str, target: str) -> str:
    url = "https://api.mymemory.translated.net/get"
    data = http_get_json(url, {"q": text, "langpair": f"fa|{target}"})
    out = data.get("responseData", {}).get("translatedText") or text
    return out


def translate_text(text: str, target: str, backend: str) -> str:
    if not text or not text.strip():
        return text
    if _PLACEHOLDER.fullmatch(text.strip()):
        return text  # فقط جای‌نگهدار است؛ چیزی برای ترجمه نیست
    protected, parts = protect_placeholders(text)
    if backend == "google":
        result = google_translate_batch([protected], target)[0]
    else:
        result = mymemory_translate(protected, target)
    return restore_placeholders(result, parts)


def load_existing(code: str) -> dict[str, str]:
    path = LOCAL / f"{code}.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def validate_flags() -> None:
    """هر زبان باید یک پرچم واقعی داخل اپ داشته باشد (بدون هیچ فونتی)."""
    missing = []
    for code in LANGUAGES:
        country = LANGUAGE_FLAG_COUNTRY.get(code, code)
        if not (FLAGS_DIR / f"{country}.svg").exists():
            missing.append(f"{code} -> {country}.svg")
    if missing:
        print("⚠️  زبان‌های بدون پرچم باندل‌شده:", ", ".join(missing))
    else:
        print(f"✅ هر {len(LANGUAGES)} زبان یک پرچم SVG واقعی داخل اپ دارد.")


def translate_locales(
    fa: dict[str, str],
    en: dict[str, str],
    langs: list[str],
    force: bool,
    offline: bool,
    backend: str,
    dry_run: bool,
) -> None:
    LOCAL.mkdir(parents=True, exist_ok=True)
    for code in langs:
        if code == "fa":
            data = dict(fa)
        elif code == "en":
            data = dict(en)
        else:
            existing = load_existing(code)
            data = dict(existing)
            todo = []
            for k, v in fa.items():
                if k not in data or data[k] == v:
                    todo.append(k)  # ناقص یا هنوز ترجمه‌نشده (همان فارسی)
                elif force:
                    todo.append(k)
            if offline:
                # بدون اینترنت نمی‌توان دوباره ترجمه کرد؛ فقط جاهای خالی/ترجمه‌نشده
                for k in todo:
                    if k not in data or data[k] == fa[k]:
                        data[k] = en.get(k, fa[k])
            else:
                for i in range(0, len(todo), 40):
                    batch = todo[i : i + 40]
                    try:
                        results = google_translate_batch(batch, code)
                    except Exception as exc:
                        print(f"   خطا در ترجمهٔ {code} (دستهٔ {i}): {exc}")
                        results = [en.get(k, fa[k]) for k in batch]
                    for k, res in zip(batch, results):
                        data[k] = res or en.get(k, fa[k])
                    if backend == "google":
                        time.sleep(0.3)
            data = dict(sorted(data.items()))
        if dry_run:
            missing = sum(1 for k in fa if k not in data)
            print(f"[dry-run] {code}: {len(data)} کلید، {missing} ناقص")
            continue
        (LOCAL / f"{code}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"✍️  {code}.json نوشته شد ({len(data)} کلید)")


def validate_parity(fa: dict[str, str]) -> None:
    issues = []
    for path in LOCAL.glob("*.json"):
        if path.name == "manifest.json":
            continue
        code = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))
        miss = set(fa) - set(data)
        extra = set(data) - set(fa)
        if miss or extra:
            issues.append(f"{code}: missing={len(miss)} extra={len(extra)}")
        for k in fa:
            fph = set(_PLACEHOLDER.findall(fa[k]))
            if fph and set(_PLACEHOLDER.findall(data.get(k, ""))) != fph:
                issues.append(f"{code}: placeholder mismatch در {k}")
    if issues:
        for it in issues[:30]:
            print("ISSUE", it)
        sys.exit("پارتی کلیدها برقرار نیست — بسته ساخته نشد.")
    count = len(list(LOCAL.glob("*.json"))) - 1
    print(f"✅ پارتی برقرار است: {count} فایل زبان × {len(fa)} کلید")


def repo_base() -> str:
    """آدرس release را از remote گیت‌هاب خودِ کاربر می‌خواند."""
    try:
        out = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, check=False,
        )
        m = re.search(r"(?:github\.com[:/])([^/]+/[^/.]+)", out.stdout.strip())
        if m:
            return f"https://github.com/{m.group(1)}/releases/download/langpacks-latest"
    except Exception:
        pass
    # پیش‌فرض: همان ریپوی مانیفستِ داخل اپ
    return "https://github.com/abtin123/Make-langueg/releases/download/langpacks-latest"


def build_packs(fa: dict[str, str]) -> None:
    OUT.mkdir(exist_ok=True)
    base = repo_base()
    languages = []
    for code in LANGUAGES:
        path = LOCAL / f"{code}.json"
        if not path.exists():
            print(f"⚠️  {code}.json پیدا نشد؛ رد شد.")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        raw = json.dumps(
            data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        packed = gzip.compress(raw, compresslevel=9, mtime=0)
        (OUT / f"lang_{code}.abl").write_bytes(packed)
        languages.append({
            "language_code": code,
            "language": NATIVE_NAMES.get(code, code),
            "direction": "rtl" if code in RTL else "ltr",
            "string_count": len(data),
            "size": len(packed),
            "sha256": hashlib.sha256(packed).hexdigest(),
            "version": hashlib.sha256(raw).hexdigest()[:16],
            "download_url": f"{base}/lang_{code}.abl",
        })
    manifest = {
        "schema_version": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "app_strings": "non-map-ui",
        "base_language": "fa",
        "string_count": len(fa),
        "languages": sorted(languages, key=lambda x: x["language_code"]),
    }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"📦 {len(languages)} بستهٔ .abl + manifest.json در {OUT} ساخته شد.")


def publish() -> None:
    subprocess.run(["git", "add", "assets/local", "tool/l10n"], check=False)
    subprocess.run(
        ["git", "commit", "-m", "chore(l10n): ترجمهٔ خودکار متن‌های جدید UI"],
        check=False,
    )
    subprocess.run(["git", "push"], check=False)
    print("🚀 push انجام شد. حالا release را منتشر کن:")
    print(
        "   gh release create langpacks-latest out/lang_*.abl out/manifest.json "
        "--clobber --title 'Language packs (latest)'"
    )


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ترجمهٔ خودکار UI اپ و انتشار بسته‌های زبان")
    p.add_argument("--langs", default=",".join(LANGUAGES),
                   help="زبان‌های هدف (مثلاً tr,de)")
    p.add_argument("--force", action="store_true",
                   help="همهٔ کلیدها را دوباره ترجمه کن")
    p.add_argument("--offline", action="store_true",
                   help="بدون اینترنت؛ جاهای خالی با انگلیسی")
    p.add_argument("--backend", choices=["google", "mymemory"], default="google")
    p.add_argument("--dry-run", action="store_true",
                   help="فقط برنامه را نشان بده، چیزی ننویس")
    p.add_argument("--no-publish", action="store_true", help="git push نکن")
    p.add_argument("--build-only", action="store_true",
                   help="فقط بسته‌ها را از JSONهای موجود بساز")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    source = SOURCE.read_text(encoding="utf-8")
    fa = extract(source, "fa")
    en = extract(source, "en")
    if len(fa) < 500 or set(fa) != set(en):
        sys.exit(f"استخراج ناموفق: fa={len(fa)} en={len(en)}")
    print(f"🔑 {len(fa)} کلید رابط کاربری استخراج شد (فارسی = منبع).")
    validate_flags()

    langs = [c.strip().lower() for c in args.langs.split(",") if c.strip()]
    for c in langs:
        if c not in LANGUAGES:
            sys.exit(f"زبان ناشناخته: {c}")

    if args.build_only:
        build_packs(fa)
        return

    translate_locales(fa, en, langs, args.force, args.offline, args.backend,
                      args.dry_run)
    if args.dry_run:
        return
    validate_parity(fa)
    build_packs(fa)
    if not args.no_publish:
        publish()


if __name__ == "__main__":
    main()
