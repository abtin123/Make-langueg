#!/usr/bin/env python3
"""Static contract checks for complete non-map language packages."""

import json
from pathlib import Path


builder = Path(__file__).resolve().parents[1]
project = builder.parent / "work"
source = json.loads((builder / "examples/base_strings.json").read_text(encoding="utf-8"))
packer = (builder / "scripts/build.py").read_text(encoding="utf-8")
catalog_data = (builder / "scripts/language_catalog.py").read_text(encoding="utf-8")
workflow = (builder / ".github/workflows/build-and-publish-langpacks.yml").read_text(encoding="utf-8")
catalog = (project / "lib/features/language_settings/data/language_pack_catalog.dart").read_text(encoding="utf-8")
service = (project / "lib/features/language_settings/data/language_pack_service.dart").read_text(encoding="utf-8")
main = (project / "lib/main.dart").read_text(encoding="utf-8")
downloads = (project / "lib/features/downloads/downloads_providers.dart").read_text(encoding="utf-8")

assert len(source) >= 300
assert all(isinstance(key, str) and isinstance(value, str) for key, value in source.items())
assert not (builder / "scripts/generate_full_locales.py").exists()
assert "LANGUAGES" in catalog_data
assert "app_strings\": \"non-map-ui" in packer
assert "lang_{code}.lpk" in packer and "sha256" in packer and "download_url" in packer
assert "gh release upload" in workflow and "--clobber" in workflow
assert "TRANSLATION_API" not in workflow
assert "lang_$code.lpk" in catalog
assert "GZipDecoder" in service and "sha256.convert" in service
assert "AppStrings.baseKeys" in service and "schema_version'] != 2" in service and "app_strings'] != 'non-map-ui'" in service
assert "Locale('ar')" in main and "Locale('zh')" in main
assert "{'fa', 'ar', 'he', 'ur'}" in main
assert "loading: () => AsyncData(builtIn)" in downloads
assert "error: (_, __) => AsyncData(builtIn)" in downloads

print("language_pack_contract_ok")
