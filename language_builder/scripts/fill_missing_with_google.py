#!/usr/bin/env python3
"""Fill missing locale strings through batched Google Translate web responses."""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


LANGUAGE_CODES = {
    "ar": "ar", "cs": "cs", "da": "da", "de": "de", "el": "el", "es": "es",
    "fi": "fi", "fr": "fr", "he": "he", "hi": "hi", "hu": "hu", "id": "id",
    "it": "it", "ja": "ja", "ko": "ko", "nl": "nl", "no": "no", "pl": "pl",
    "pt": "pt", "ro": "ro", "ru": "ru", "sv": "sv", "th": "th", "tr": "tr",
    "uk": "uk", "ur": "ur", "vi": "vi", "zh": "zh-CN",
}


def _placeholder_set(text: str) -> set[str]:
    return set(re.findall(r"\{[^{}]+\}", text))


def _translate(target: str, items: list[tuple[str, str]]) -> dict[str, str]:
    payload = "\n".join(f"[[[ABTIN_{key}]]] {value}" for key, value in items)
    query = urllib.parse.urlencode({
        "client": "gtx", "sl": "fa", "tl": target, "dt": "t", "q": payload,
    })
    request = urllib.request.Request(
        f"https://translate.googleapis.com/translate_a/single?{query}",
        headers={"user-agent": "AbtinMapsLanguageBuilder/1.0"},
    )
    with urllib.request.urlopen(request, timeout=35) as response:
        data = json.loads(response.read().decode("utf-8"))
    translated = "".join(part[0] for part in data[0] if part and part[0])
    matches = re.findall(r"\[\[\[ABTIN_([^\]]+)\]\]\]\s*(.*?)(?=\n?\[\[\[ABTIN_|$)", translated, flags=re.S)
    output = {key: value.strip() for key, value in matches}
    expected = {key for key, _ in items}
    if set(output) != expected:
        raise RuntimeError("translated chunk lost an ABTIN key delimiter")
    for key, source in items:
        if _placeholder_set(source) != _placeholder_set(output[key]):
            raise RuntimeError(f"translated chunk changed placeholders for {key}")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("examples/base_strings.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--codes", nargs="*", default=None)
    args = parser.parse_args()
    base = json.loads(args.source.read_text(encoding="utf-8"))
    selected = args.codes or sorted(LANGUAGE_CODES)
    for code in selected:
        if code not in LANGUAGE_CODES:
            raise ValueError(f"Unsupported locale: {code}")
        path = args.locales_dir / f"{code}.json"
        try:
            current = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            current = {}
        if not isinstance(current, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in current.items()):
            current = {}
        missing = [(key, value) for key, value in base.items() if key not in current]
        for start in range(0, len(missing), 16):
            chunk = missing[start:start + 16]
            for attempt in range(3):
                try:
                    current.update(_translate(LANGUAGE_CODES[code], chunk))
                    break
                except Exception:
                    if attempt == 2:
                        raise
                    time.sleep(2 ** attempt)
        path.write_text(json.dumps(current, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{code}: completed {len(missing)} keys", flush=True)


if __name__ == "__main__":
    main()
