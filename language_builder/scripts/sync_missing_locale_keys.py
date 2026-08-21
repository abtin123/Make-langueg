#!/usr/bin/env python3
"""Translate only UI keys absent from existing language locale files."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import time
from pathlib import Path

from openai import OpenAI

from language_catalog import LANGUAGES


def _chunks(values: list[tuple[str, str]], size: int = 24):
    for index in range(0, len(values), size):
        yield values[index:index + size]


def _decode_json(content: str, expected: set[str]) -> dict[str, str]:
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", content.strip(), flags=re.I)
    decoded = json.loads(text)
    if not isinstance(decoded, dict) or set(decoded) != expected:
        raise ValueError("translation response did not preserve the requested keys")
    if not all(isinstance(value, str) and value.strip() for value in decoded.values()):
        raise ValueError("translation response contains an empty non-string value")
    return decoded


def _translate(client: OpenAI, code: str, name: str, items: list[tuple[str, str]]) -> dict[str, str]:
    payload = dict(items)
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            response = client.chat.completions.create(
                model="gpt-5-nano",
                messages=[
                    {
                        "role": "system",
                        "content": "You translate navigation app UI precisely. Return JSON only.",
                    },
                    {
                        "role": "user",
                        "content": (
                            f"Translate these Persian Abtin Maps mobile UI strings into {name} ({code}). "
                            "Return exactly the same keys as compact natural UI text. Preserve placeholders, "
                            "numbers, punctuation, HUD, AI Camera, DashCam and proper product names.\n\n"
                            + json.dumps(payload, ensure_ascii=False)
                        ),
                    },
                ],
                max_completion_tokens=4000,
                extra_body={"reasoning": {"effort": "minimal"}},
            )
            if not response.choices:
                raise RuntimeError("translation model returned no choices")
            return _decode_json(response.choices[0].message.content or "", set(payload))
        except Exception as error:
            last_error = error
            time.sleep(2 ** attempt)
    raise RuntimeError(f"{code} translation failed after retries: {last_error}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("examples/base_strings.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--codes", nargs="*", default=None)
    args = parser.parse_args()

    base = json.loads(args.source.read_text(encoding="utf-8"))
    client = OpenAI()
    selected = args.codes or sorted(LANGUAGES)

    for code in selected:
        if code not in LANGUAGES:
            raise ValueError(f"Unsupported locale: {code}")
        path = args.locales_dir / f"{code}.json"
        current = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        missing = [(key, value) for key, value in base.items() if key not in current]
        if not missing:
            print(f"{code}: already synchronized", flush=True)
            continue
        if code == "fa":
            current.update(dict(missing))
        else:
            name = LANGUAGES[code][0]
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
                futures = [
                    executor.submit(_translate, client, code, name, chunk)
                    for chunk in _chunks(missing)
                ]
                for future in futures:
                    current.update(future.result())
        path.write_text(json.dumps(current, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{code}: added {len(missing)} keys", flush=True)


if __name__ == "__main__":
    main()
