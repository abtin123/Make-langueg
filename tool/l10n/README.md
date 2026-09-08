# ترجمهٔ خودکار اپ و انتشار زبان‌ها

این ابزار همهٔ متن‌های رابط کاربری اپ (AbtinMaps) را به ۳۰ زبان ترجمه می‌کند،
بستهٔ هر زبان را می‌سازد و روی گیت‌هاب منتشر می‌کند تا هر کسی زبان دلخواهش را
دانلود کند.

## چه چیزی ترجمه می‌شود؟

همهٔ متن‌های UI که در `lib/core/localization/app_localizations.dart` هستند —
حدود ۵۸۵ کلید که شامل این‌هاست:

- منوی پایین و همهٔ صفحه‌های تنظیمات
- **کارت مسیریابی** (فاصله، ETA، زمان باقی‌مانده، دستورهای پیچ‌به‌پیچ مثل «به راست بپیچ»)
- جستجو، علاقه‌مندی‌ها، صدا و اعلان‌ها
- HUD، دوربین هوشمند، آب‌وهوا، نقشهٔ آفلاین و دانلود نقشه
- پیام‌های خطا و همهٔ متن‌های دیگر اپ

## چه چیزی ترجمه نمی‌شود؟

- **خودِ نقشه.** برچسب‌های نقشه از دادهٔ محلیِ خودِ نقشه می‌آیند؛ نقشهٔ ایران
  فارسی می‌ماند، نقشهٔ ترکیه ترکی می‌ماند و ... — دقیقاً همان‌طور که خواستی.
  این اسکریپت فقط متن‌های UI را لمس می‌کند و هیچ‌وقت دادهٔ نقشه را ترجمه نمی‌کند.
- **هیچ فونت پرچمی اضافه نمی‌شود.** پرچم هر زبان از assetهای SVG خودِ اپ
  (`assets/images/flags/*.svg`) رندر می‌شود — برای هر ۳۰ زبان یک پرچم واقعی
  داخل خودِ APK هست (جدول پایین).

## اجرای محلی

```bash
# ترجمهٔ کلیدهای ناقص + ساخت بسته‌ها + push روی گیت‌هاب
python tool/l10n/translate_and_publish.py

# فقط ترجمه و ساخت (بدون push)
python tool/l10n/translate_and_publish.py --no-publish

# فقط ساخت بسته‌ها از JSONهای موجود
python tool/l10n/translate_and_publish.py --build-only

# بدون اینترنت (جاهای خالی با انگلیسی پر می‌شود)
python tool/l10n/translate_and_publish.py --offline

# فقط چند زبان خاص، بدون تغییر فایل
python tool/l10n/translate_and_publish.py --langs tr,de --dry-run
```

نیازمندی: `pip install requests` (یا بدون آن هم با urllib استاندارد کار می‌کند).

## اجرا روی گیت‌هاب (پیشنهادی)

1. پروژه را به گیت‌هاب push کن (فایل‌های `tool/l10n/` و
   `.github/workflows/translate-publish.yml` باید داخل ریپو باشند).
2. برو به تب **Actions** → **Translate & Publish Language Packs** → **Run workflow**.
3. اکشن همهٔ زبان‌ها را ترجمه می‌کند، بسته‌ها را روی release با تگ
   `langpacks-latest` منتشر می‌کند و JSONهای به‌روزشده را برمی‌گرداند.

## کاربر چطور زبان را دانلود کند؟

- **داخل اپ:** در تنظیمات زبان، هر زبانی را انتخاب کند؛ اپ مانیفست را از
  `releases/download/langpacks-latest/manifest.json` می‌خواند و بستهٔ همان زبان
  را دانلود می‌کند.
- **دستی:** از صفحهٔ Release همان ریپو، فایل `lang_<code>.abl` را دانلود کند.

## افزودن زبان جدید

1. کد زبان را به لیست `LANGUAGES` در `translate_and_publish.py` اضافه کن
   (و در صورت نیاز `NATIVE_NAMES` و `LANGUAGE_FLAG_COUNTRY`).
2. اگر پرچمش در `assets/images/flags/` نبود، یک SVG با نام کد کشور اضافه کن.
3. اسکریپت را اجرا کن.

## جدول زبان → پرچم (همه از assetهای داخل اپ)

| زبان | کد | پرچم (asset) |
|------|-----|--------------|
| فارسی | fa | ir.svg |
| English | en | gb.svg |
| العربية | ar | sa.svg |
| Türkçe | tr | tr.svg |
| اردو | ur | pk.svg |
| Русский | ru | ru.svg |
| Français | fr | fr.svg |
| Deutsch | de | de.svg |
| Español | es | es.svg |
| Italiano | it | it.svg |
| 中文 | zh | cn.svg |
| हिन्दी | hi | in.svg |
| Čeština | cs | cz.svg |
| Dansk | da | dk.svg |
| Ελληνικά | el | gr.svg |
| Suomi | fi | fi.svg |
| עברית | he | il.svg |
| Magyar | hu | hu.svg |
| Bahasa Indonesia | id | id.svg |
| 日本語 | ja | jp.svg |
| 한국어 | ko | kr.svg |
| Nederlands | nl | nl.svg |
| Norsk | no | no.svg |
| Polski | pl | pl.svg |
| Português | pt | pt.svg |
| Română | ro | ro.svg |
| Svenska | sv | se.svg |
| ไทย | th | th.svg |
| Українська | uk | ua.svg |
| Tiếng Việt | vi | vn.svg |
