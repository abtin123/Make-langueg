#!/usr/bin/env python3
"""Translate the full flat UI catalog through an OpenAI-compatible endpoint."""

from __future__ import annotations

import argparse
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path


LANGUAGES = {
    "ar": ("Arabic", "العربية", "🇸🇦", "rtl"), "cs": ("Czech", "Čeština", "🇨🇿", "ltr"),
    "da": ("Danish", "Dansk", "🇩🇰", "ltr"), "de": ("German", "Deutsch", "🇩🇪", "ltr"),
    "el": ("Greek", "Ελληνικά", "🇬🇷", "ltr"), "es": ("Spanish", "Español", "🇪🇸", "ltr"),
    "fi": ("Finnish", "Suomi", "🇫🇮", "ltr"), "fr": ("French", "Français", "🇫🇷", "ltr"),
    "he": ("Hebrew", "עברית", "🇮🇱", "rtl"), "hi": ("Hindi", "हिन्दी", "🇮🇳", "ltr"),
    "hu": ("Hungarian", "Magyar", "🇭🇺", "ltr"), "id": ("Indonesian", "Bahasa Indonesia", "🇮🇩", "ltr"),
    "it": ("Italian", "Italiano", "🇮🇹", "ltr"), "ja": ("Japanese", "日本語", "🇯🇵", "ltr"),
    "ko": ("Korean", "한국어", "🇰🇷", "ltr"), "nl": ("Dutch", "Nederlands", "🇳🇱", "ltr"),
    "no": ("Norwegian", "Norsk", "🇳🇴", "ltr"), "pl": ("Polish", "Polski", "🇵🇱", "ltr"),
    "pt": ("Portuguese", "Português", "🇵🇹", "ltr"), "ro": ("Romanian", "Română", "🇷🇴", "ltr"),
    "ru": ("Russian", "Русский", "🇷🇺", "ltr"), "sv": ("Swedish", "Svenska", "🇸🇪", "ltr"),
    "th": ("Thai", "ไทย", "🇹🇭", "ltr"), "tr": ("Turkish", "Türkçe", "🇹🇷", "ltr"),
    "uk": ("Ukrainian", "Українська", "🇺🇦", "ltr"), "ur": ("Urdu", "اردو", "🇵🇰", "rtl"),
    "vi": ("Vietnamese", "Tiếng Việt", "🇻🇳", "ltr"), "zh": ("Simplified Chinese", "简体中文", "🇨🇳", "ltr"),
}


def call_api(*, base_url: str, api_key: str, model: str, language: str, values: dict[str, str]) -> dict[str, str]:
    prompt = (
        f"Translate every value in this JSON object from Persian to {language}. "
        "Keep keys exactly unchanged. Preserve all placeholders such as {name}, {count}, {error}, "
        "and punctuation placeholders exactly. Do not translate product names Abtin Maps/آبتین مپس. "
        "Do not add, remove, merge, or reorder keys. Return JSON only.\n\n"
        + json.dumps(values, ensure_ascii=False, separators=(",", ":"))
    )
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a precise mobile-app localization translator. Output valid JSON only."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.1,
        "max_completion_tokens": 4000,
        "response_format": {"type": "json_object"},
    }).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions", data=payload, method="POST",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=75) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Translation API HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}") from error
    content = body["choices"][0]["message"]["content"]
    if not isinstance(content, str):
        raise RuntimeError("Translation API did not return text")
    parsed = json.loads(content)
    if not isinstance(parsed, dict):
        raise RuntimeError("Translation API result is not an object")
    return {str(key): str(value) for key, value in parsed.items()}


def validate(source: dict[str, str], translated: dict[str, str]) -> None:
    if set(source) != set(translated):
        missing = sorted(set(source) - set(translated))[:10]
        extra = sorted(set(translated) - set(source))[:10]
        raise ValueError(f"Translation keys differ; missing={missing}, extra={extra}")
    for key, source_value in source.items():
        target_value = translated[key]
        source_markers = set(re.findall(r"\{[^}]+\}", source_value))
        target_markers = set(re.findall(r"\{[^}]+\}", target_value))
        if source_markers != target_markers:
            raise ValueError(f"Placeholder mismatch in {key}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("examples/base_strings.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--codes", nargs="*", default=sorted(LANGUAGES))
    parser.add_argument("--model", default=os.environ.get("TRANSLATION_MODEL", "gpt-5-mini"))
    parser.add_argument("--base-url", default=os.environ.get("TRANSLATION_API_BASE", os.environ.get("OPENAI_API_BASE", "")))
    parser.add_argument("--api-key", default=os.environ.get("TRANSLATION_API_KEY", os.environ.get("OPENAI_API_KEY", "")))
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--chunk-size", type=int, default=40)
    args = parser.parse_args()
    if not args.base_url or not args.api_key:
        raise SystemExit("Set TRANSLATION_API_BASE and TRANSLATION_API_KEY (or compatible OPENAI_* values).")
    source = json.loads(args.source.read_text(encoding="utf-8"))
    args.locales_dir.mkdir(parents=True, exist_ok=True)
    for code in args.codes:
        if code not in LANGUAGES:
            raise SystemExit(f"Unsupported language code: {code}")
        output = args.locales_dir / f"{code}.json"
        if output.exists() and not args.overwrite:
            print(f"skip existing: {code}")
            continue
        language, _native, _flag, _direction = LANGUAGES[code]
        for attempt in range(3):
            try:
                translated = {}
                entries = list(source.items())
                for index in range(0, len(entries), args.chunk_size):
                    chunk = dict(entries[index:index + args.chunk_size])
                    print(f"translate {code}: {index // args.chunk_size + 1}/{(len(entries) + args.chunk_size - 1) // args.chunk_size}", flush=True)
                    translated.update(call_api(base_url=args.base_url, api_key=args.api_key, model=args.model, language=language, values=chunk))
                validate(source, translated)
                output.write_text(json.dumps(translated, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                print(f"translated {code}: {len(translated)} strings")
                break
            except Exception as error:
                if attempt == 2:
                    raise
                print(f"retry {code}: {error}")
                time.sleep(2 ** attempt)


if __name__ == "__main__":
    main()
