#!/usr/bin/env python3
"""Static contract checks for the incremental, complete language-pack builder."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def read_flat(path: Path) -> dict[str, str]:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), f"{path} is not a JSON object"
    assert all(isinstance(key, str) and isinstance(text, str) for key, text in value.items()), (
        f"{path} is not a flat string table"
    )
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=None)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    builder = Path(__file__).resolve().parents[1]
    source = read_flat(builder / "examples/base_strings.json")
    packer = (builder / "scripts/build.py").read_text(encoding="utf-8")
    translator = (builder / "scripts/complete_locales_internal.py").read_text(encoding="utf-8")
    workflow = (builder / ".github/workflows/build-and-publish-langpacks.yml").read_text(encoding="utf-8")
    readme = (builder / "README.md").read_text(encoding="utf-8")

    assert len(source) >= 300
    assert "--fill-missing" not in packer
    assert "--skip-incomplete" not in packer
    assert "fallback_key_count" not in packer
    assert "source_sha256" in translator
    assert ".locale-checkpoints" in translator
    assert "changed" in translator and "retained" in translator
    assert "--force-full" in translator
    assert "response_format=json_schema" in translator
    assert "--fill-missing" not in workflow
    assert "Complete changed language strings before publishing" in workflow
    assert "Validate and build complete language packs" in workflow
    assert "complete_locales_internal.py" in workflow
    assert "OPENAI_API_KEY" in workflow
    assert "به‌روزرسانی تفاضلی" in readme
    assert "fallback" in readme

    if args.require_complete:
        expected = set(source)
        for locale in sorted((builder / "locales").glob("*.json")):
            values = read_flat(locale)
            assert set(values) == expected, f"{locale.name} is incomplete"
            assert all(value.strip() for value in values.values()), f"{locale.name} has blank strings"

    project = args.project
    if project is None:
        configured = os.environ.get("ABTIN_APP_ROOT")
        project = Path(configured) if configured else None
    if project is not None:
        catalog = (project / "lib/features/language_settings/data/language_pack_catalog.dart").read_text(encoding="utf-8")
        service = (project / "lib/features/language_settings/data/language_pack_service.dart").read_text(encoding="utf-8")
        main_dart = (project / "lib/main.dart").read_text(encoding="utf-8")
        assert "code: 'zh'" not in catalog
        assert "_validateCompleteValues" in service
        assert "requiredCount = AppStrings.baseKeys.length" in service
        assert "assets/locales/zh.json" not in service
        assert "Locale('zh')" in main_dart

    print("language_pack_contract_ok")


if __name__ == "__main__":
    main()
