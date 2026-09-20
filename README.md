# AbtinMaps Language Pack Builder

`fa.json` is the Persian source localization.

**Important:** Persian (`fa`) and English (`en`) are local languages and are NOT
generated or modified by this builder. The builder creates only the 28 remote
language packs listed in `languages.json`.

## GitHub Secrets

Add:
- `GCP_SERVICE_ACCOUNT_JSON`
- `GOOGLE_CLOUD_PROJECT`

Enable Google Cloud Translation API for the project.

## Local run

```bash
pip install -r requirements.txt
export GOOGLE_CLOUD_PROJECT="your-project-id"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

python generate_languages.py --input fa.json --output output
```

The script:
- keeps `fa` and `en` untouched
- generates only the 28 target languages
- preserves all source keys
- protects placeholders, URLs and markup
- caches translations
- validates that every generated language has exactly the same keys as `fa.json`
- creates `lang_<code>.abl` files and a manifest
