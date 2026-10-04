# Make-Langueg — language packs / بسته‌های زبان

## English
Translates the app's English strings into 28 languages and publishes them to a GitHub Release that the app downloads from (`.../abtin123/Make-langueg/releases/download/langpacks-latest`).

- Source: `source/en.json` (copy of the app's `assets/local/en.json`; key → English). Refresh it whenever app strings change.
- Output: `lang_<code>.abl` (gzip of UTF-8 JSON) + `manifest.json`. `fa` and `en` are bundled in the APK and are not generated.
- Placeholders such as `{name}` / `{count}` and brand terms (Abtin Maps, GPS, AQI…) are protected. If an engine damages a placeholder, that string safely falls back to English.
- Only new or changed strings are translated (cache `.l10n_cache`).
- Human fixes: put `overrides/<code>.json` (`{"key": "text"}`); overrides always win. Extra do-not-translate terms: `glossary.json` (JSON list).

```bash
pip install -r requirements.txt
python scripts/translate_langpacks.py --engine google                 # all languages
python scripts/translate_langpacks.py --engine google --languages tr,de
python scripts/translate_langpacks.py --engine anthropic              # needs ANTHROPIC_API_KEY
python scripts/translate_langpacks.py --engine mock --languages tr    # offline test
```

Publish: **Actions → Translate and publish language packs → Run workflow**. For the `anthropic` engine add the repo secret `ANTHROPIC_API_KEY`.

## فارسی
متن‌های انگلیسی اپ را به ۲۸ زبان ترجمه می‌کند و در GitHub Release منتشر می‌کند؛ اپ بسته‌ها را از `langpacks-latest` دانلود می‌کند.

- منبع: `source/en.json` (کپی `assets/local/en.json` اپ؛ کلید ← متن انگلیسی). هر وقت متن‌های اپ عوض شد، دوباره کپی کنید.
- خروجی: `lang_<code>.abl` (فایل gzip شده‌ی JSON) و `manifest.json`. زبان‌های `fa` و `en` داخل APK هستند و ساخته نمی‌شوند.
- متغیرهایی مثل `{name}` و `{count}` و نام‌های برند (Abtin Maps، GPS، AQI و …) دست‌نخورده می‌مانند. اگر موتور ترجمه متغیری را خراب کند، همان رشته به انگلیسی برمی‌گردد.
- فقط رشته‌های جدید یا تغییرکرده ترجمه می‌شوند (کش `.l10n_cache`).
- اصلاح دستی: فایل `overrides/<code>.json` (`{"کلید": "متن"}`)؛ همیشه بر ترجمه‌ی خودکار مقدم است. عبارت‌های ترجمه‌نشدنی بیشتر: `glossary.json` (لیست JSON).

انتشار: **Actions ← Translate and publish language packs ← Run workflow**. برای موتور `anthropic` باید secret با نام `ANTHROPIC_API_KEY` در ریپو بسازید.
