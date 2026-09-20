# AbtinMaps Translation Builder — No API

این نسخه به Google Cloud API، Service Account، API Key یا Project ID نیاز ندارد.

ورودی:
- `fa.json`

خروجی:
- `dist/<lang>.json`
- `dist/lang_<lang>.abl`
- `dist/manifest.json`

زبان‌های `fa` و `en` محلی هستند و هیچ‌وقت ساخته یا تغییر داده نمی‌شوند.

اجرای محلی:

```bash
pip install -r requirements.txt
python generate_languages.py
```

اجرای یک زبان:

```bash
python generate_languages.py --targets de
```

برای اجرای مجدد، کش `.translation_cache.json` باعث می‌شود متن‌هایی که قبلاً ترجمه شده‌اند دوباره ترجمه نشوند.

این نسخه از endpoint عمومی وب Google Translate استفاده می‌کند؛ بنابراین «بدون API» است، اما چون API رسمی نیست ممکن است Google در مقاطعی نرخ درخواست را محدود کند. برای همین retry، delay و cache دارد.

فرمت `.abl` همان فرمت builder قبلی است:
UTF-8 JSON فشرده‌شده با gzip و پسوند `.abl`.
