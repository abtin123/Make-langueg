#!/usr/bin/env python3
"""Complete non-map UI locale JSON files with the sandbox's internal LLM proxy."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import time
from pathlib import Path

from openai import OpenAI

from language_catalog import LANGUAGES


def chunks(values: list[tuple[str, str]], size: int = 32):
    for index in range(0, len(values), size):
        yield values[index:index + size]


def clean_json(content: str) -> dict[str, str]:
    content = content.strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content, flags=re.I)
    value = json.loads(content)
    if not isinstance(value, dict) or not all(isinstance(key, str) and isinstance(text, str) for key, text in value.items()):
        raise ValueError("model did not return a flat JSON string table")
    return value


def translate_chunk(code: str, name: str, values: list[tuple[str, str]]) -> dict[str, str]:
    payload = dict(values)
    prompt = f"""Translate the Persian mobile-navigation app UI strings below into {name} ({code}).
Return JSON only: exactly the same keys, each mapped to a translated string.
Preserve all placeholders such as {{count}}, {{error}}, {{distance}}, punctuation tokens and line breaks.
Do not translate map data, place names, or keys. Use concise natural mobile UI wording.

{json.dumps(payload, ensure_ascii=False)}"""
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            response = OpenAI(timeout=75.0, max_retries=1).chat.completions.create(
                model="gpt-5-nano",
                messages=[
                    {"role": "system", "content": "You are a precise software localization translator. Output valid JSON only."},
                    {"role": "user", "content": prompt},
                ],
                max_completion_tokens=2800,
            )
            result = clean_json(response.choices[0].message.content or "")
            if set(result) != set(payload):
                raise ValueError("model returned missing or extra keys")
            return result
        except Exception as error:
            last_error = error
            time.sleep(2 ** attempt)
    raise RuntimeError(f"{code} translation chunk failed: {last_error}")


def complete_locale(code: str, base: dict[str, str], locales_dir: Path) -> None:
    english_name, _, _, _ = LANGUAGES[code]
    translated: dict[str, str] = {}
    work = list(chunks(list(base.items())))
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        futures = [executor.submit(translate_chunk, code, english_name, item) for item in work]
        for future in futures:
            translated.update(future.result())
    if set(translated) != set(base):
        raise RuntimeError(f"{code} is incomplete after translation")
    (locales_dir / f"{code}.json").write_text(
        json.dumps(translated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"completed {code}: {len(translated)} strings", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="examples/base_strings.json")
    parser.add_argument("--locales-dir", default="locales")
    parser.add_argument("--codes", nargs="*", default=None)
    args = parser.parse_args()
    base = json.loads(Path(args.source).read_text(encoding="utf-8"))
    selected = args.codes or sorted(LANGUAGES)
    for code in selected:
        if code not in LANGUAGES:
            raise ValueError(f"Unsupported locale {code}")
        complete_locale(code, base, Path(args.locales_dir))


if __name__ == "__main__":
    main()
