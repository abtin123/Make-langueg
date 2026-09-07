#!/usr/bin/env python3
"""Generate complete UI locale files, incrementally and without fallback text.

For each target language, the tool stores the exact Persian source table that
was used for its last completed translation. On later runs, only new keys or
keys whose Persian source text changed are sent to the translation model;
unchanged, validated translations are reused. Partial progress is checkpointed
after every successful batch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import time
from pathlib import Path
from typing import Iterable

from openai import OpenAI

from language_catalog import LANGUAGES

DEFAULT_MODEL = "gpt-5-mini"
PLACEHOLDER = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")
PERSIAN_SPECIFIC_LETTER = re.compile(r"[پچژگکی]")
BRAND_IDENTITY_KEYS = {"app_name"}


def chunks(values: list[tuple[str, str]], size: int) -> Iterable[list[tuple[str, str]]]:
    for index in range(0, len(values), size):
        yield values[index:index + size]


def read_flat(path: Path) -> dict[str, str]:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict) or not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in decoded.items()
    ):
        raise ValueError(f"{path} must be a flat JSON string table")
    return decoded


def read_optional_flat(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return read_flat(path)


def write_flat(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(values, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def source_digest(source: dict[str, str]) -> str:
    encoded = json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def validate_value(*, code: str, key: str, source: str, value: str) -> None:
    if not value.strip():
        raise ValueError(f"{key}: empty translation")
    if set(PLACEHOLDER.findall(value)) != set(PLACEHOLDER.findall(source)):
        raise ValueError(f"{key}: placeholder set changed")
    if key in BRAND_IDENTITY_KEYS:
        return
    # LTR targets may legitimately contain neutral Persian/Arabic punctuation
    # (for example the Persian percent sign). Persian-specific letters are the
    # reliable signal of an accidental fallback sentence.
    if code not in {"ar", "ur"} and PERSIAN_SPECIFIC_LETTER.search(value):
        raise ValueError(f"{key}: Persian fallback text leaked into {code}")
    # Arabic should use Arabic glyphs, not Persian-only letters found in a
    # fallback string. Urdu is deliberately exempt because it uses these glyphs.
    if code == "ar" and PERSIAN_SPECIFIC_LETTER.search(value):
        raise ValueError(f"{key}: Persian fallback text leaked into Arabic")
    # An unchanged Persian phrase is only safe for neutral product/acronym keys.
    if (
        code != "ur"
        and value == source
        and PERSIAN_SPECIFIC_LETTER.search(source)
    ):
        raise ValueError(f"{key}: Persian source leaked unchanged")


def validate_complete(*, code: str, source: dict[str, str], values: dict[str, str]) -> None:
    expected = set(source)
    actual = set(values)
    if actual != expected:
        raise ValueError(
            f"{code} is incomplete; missing={len(expected - actual)}, extra={len(actual - expected)}"
        )
    for key, original in source.items():
        validate_value(code=code, key=key, source=original, value=values[key])


def json_schema(keys: list[str]) -> dict[str, object]:
    return {
        "type": "json_schema",
        "json_schema": {
            "name": "localized_ui_strings",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {key: {"type": "string"} for key in keys},
                "required": keys,
                "additionalProperties": False,
            },
        },
    }


def translate_chunk(
    *, code: str, name: str, source: dict[str, str], model: str, attempts: int
) -> dict[str, str]:
    prompt = f"""Translate this Persian mobile-navigation UI table into {name} ({code}).
Return only the JSON object required by the schema. Translate every sentence naturally for a mobile app.
Preserve placeholders such as {{count}}, {{error}}, {{distance}}, all line breaks, punctuation tokens, and technical acronyms such as GPS, HUD, AI and DashCam when appropriate. The product token «آبتین مپس» may be transliterated, but surrounding phrases must be translated: for example, translate the full meaning of «درباره آبتین مپس» rather than copying Persian text. Do not translate keys. Do not leave Persian fallback text.

{json.dumps(source, ensure_ascii=False)}"""
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            response = OpenAI(timeout=90.0, max_retries=0).chat.completions.create(
                model=model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are a meticulous professional software localization translator. Return valid JSON matching the supplied schema exactly.",
                    },
                    {"role": "user", "content": prompt},
                ],
                response_format=json_schema(list(source)),
                max_completion_tokens=7000,
            )
            content = response.choices[0].message.content or ""
            translated = json.loads(content)
            if not isinstance(translated, dict) or not all(
                isinstance(key, str) and isinstance(value, str)
                for key, value in translated.items()
            ):
                raise ValueError("model did not return a flat JSON string table")
            if set(translated) != set(source):
                raise ValueError(
                    f"model returned wrong keys; missing={len(set(source) - set(translated))}, "
                    f"extra={len(set(translated) - set(source))}"
                )
            for key, original in source.items():
                validate_value(code=code, key=key, source=original, value=translated[key])
            return translated
        except Exception as error:
            last_error = error
            print(f"  retry {attempt}/{attempts}: {type(error).__name__}: {error}", flush=True)
            time.sleep(min(2**attempt, 8))
    raise RuntimeError(f"{code} translation chunk failed: {last_error}")


def valid_candidate(*, code: str, key: str, source: str, value: str) -> bool:
    try:
        validate_value(code=code, key=key, source=source, value=value)
    except ValueError:
        return False
    return True


def locale_delta(
    *, code: str, source: dict[str, str], previous_source: dict[str, str],
    candidate: dict[str, str], force_full: bool,
) -> tuple[dict[str, str], dict[str, int], list[tuple[str, str]]]:
    retained: dict[str, str] = {}
    to_translate: list[tuple[str, str]] = []
    counts = {"retained": 0, "new": 0, "changed": 0, "invalid": 0}
    for key, value in source.items():
        old_value = previous_source.get(key)
        existing = candidate.get(key)
        if force_full:
            counts["changed"] += 1
            to_translate.append((key, value))
        elif old_value is not None and old_value != value:
            counts["changed"] += 1
            to_translate.append((key, value))
        elif existing is None:
            counts["new"] += 1
            to_translate.append((key, value))
        elif valid_candidate(code=code, key=key, source=value, value=existing):
            retained[key] = existing
            counts["retained"] += 1
        else:
            counts["invalid"] += 1
            to_translate.append((key, value))
    return retained, counts, to_translate


def complete_locale(
    *, code: str, source: dict[str, str], locales_dir: Path, checkpoints_dir: Path,
    state_dir: Path, model: str, chunk_size: int, attempts: int, force_full: bool,
) -> dict[str, object]:
    english_name, _, _, _ = LANGUAGES[code]
    target = locales_dir / f"{code}.json"
    checkpoint = checkpoints_dir / f"{code}.json"
    state_file = state_dir / f"{code}.source.json"
    candidate: dict[str, str] = {}
    for path in (target, checkpoint):
        try:
            candidate.update(read_optional_flat(path))
        except (OSError, ValueError, json.JSONDecodeError):
            pass
    try:
        previous_source = read_optional_flat(state_file)
    except (OSError, ValueError, json.JSONDecodeError):
        previous_source = {}

    completed, counts, pending = locale_delta(
        code=code,
        source=source,
        previous_source=previous_source,
        candidate=candidate,
        force_full=force_full,
    )
    print(
        f"{code}: retained={counts['retained']}, new={counts['new']}, "
        f"changed={counts['changed']}, invalid={counts['invalid']}, "
        f"to_translate={len(pending)}, total={len(source)}",
        flush=True,
    )
    if pending and not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError(
            "Translation is required but OPENAI_API_KEY is not configured. "
            "For GitHub Actions, add it as the OPENAI_API_KEY repository secret."
        )
    for number, batch in enumerate(chunks(pending, chunk_size), start=1):
        translated = translate_chunk(
            code=code,
            name=english_name,
            source=dict(batch),
            model=model,
            attempts=attempts,
        )
        completed.update(translated)
        write_flat(checkpoint, completed)
        print(f"  {code}: checkpoint {len(completed)}/{len(source)} (chunk {number})", flush=True)

    validate_complete(code=code, source=source, values=completed)
    write_flat(target, completed)
    write_flat(state_file, source)
    checkpoint.unlink(missing_ok=True)
    return {
        "language_code": code,
        "source_sha256": source_digest(source),
        "total_keys": len(source),
        **counts,
        "translated_now": len(pending),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("examples/base_strings.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--checkpoints-dir", type=Path, default=Path(".locale-checkpoints"))
    parser.add_argument("--state-dir", type=Path, default=Path(".locale-state"))
    parser.add_argument("--report", type=Path, default=Path("LOCALE_DELTA_REPORT.json"))
    parser.add_argument("--codes", nargs="*", default=None)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--chunk-size", type=int, default=64)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--force-full", action="store_true")
    args = parser.parse_args()
    if not 8 <= args.chunk_size <= 96:
        raise SystemExit("chunk-size باید بین 8 و 96 باشد")
    if not 1 <= args.attempts <= 5:
        raise SystemExit("attempts باید بین 1 و 5 باشد")
    source = read_flat(args.source)
    selected = args.codes or sorted(LANGUAGES)
    results: list[dict[str, object]] = []
    for code in selected:
        if code not in LANGUAGES:
            raise ValueError(f"Unsupported locale {code}")
        if code in {"fa", "en"}:
            continue
        result = complete_locale(
            code=code,
            source=source,
            locales_dir=args.locales_dir,
            checkpoints_dir=args.checkpoints_dir,
            state_dir=args.state_dir,
            model=args.model,
            chunk_size=args.chunk_size,
            attempts=args.attempts,
            force_full=args.force_full,
        )
        results.append(result)
        print(
            f"completed {code}: {result['total_keys']} keys; translated now={result['translated_now']}",
            flush=True,
        )
    args.report.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "source_sha256": source_digest(source),
                "source_key_count": len(source),
                "languages": results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
