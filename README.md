# آبتین‌مپ — سازندهٔ بسته‌های زبان

این مخزن فقط متن‌های رابط کاربری را ترجمه و منتشر می‌کند. داده‌های نقشه، نام
کشورها، مکان‌ها، خیابان‌ها، POIها و فایل‌های ABM عمداً در بسته‌های زبان وجود
ندارند.

هر بستهٔ زبان شامل تمام **۳۱۷** کلید رابط غیرنقشه‌ای است و به‌صورت یک فایل
فشردهٔ `.lpk` منتشر می‌شود. اپ ابتدا `manifest.json` را دریافت می‌کند، سپس فقط
زبان انتخاب‌شده را دانلود، هش SHA-256 را بررسی و نصب می‌کند.

## Secretهای GitHub

در `Settings → Secrets and variables → Actions` این دو secret را ثبت کنید:

```text
TRANSLATION_API_KEY
TRANSLATION_API_BASE
```

`TRANSLATION_API_BASE` باید یک endpoint سازگار با OpenAI و شامل `/v1` باشد؛
مثلاً `https://api.openai.com/v1`. در صورت خالی‌بودن، workflow همان آدرس OpenAI
را استفاده می‌کند. مدل اختیاری در variable با نام `TRANSLATION_MODEL` قرار
می‌گیرد و مقدار پیش‌فرض `gpt-5-mini` است.

## انتشار

از Actions، workflow `build-and-publish-language-packs` را اجرا کنید. گزینهٔ
`translate` به‌طور پیش‌فرض فعال است و همهٔ localeها را از روی
`examples/base_strings.json` کامل می‌کند. سپس workflow این موارد را در release
با tag `langpacks-latest` قرار می‌دهد:

```text
manifest.json
lang_ar.lpk
lang_de.lpk
...
```

هر رکورد مانیفست دارای لینک مستقیم asset، نسخه، اندازه، تعداد کلیدها، جهت متن
و SHA-256 است. اپ فقط مانیفستِ schema version 2 با `app_strings: non-map-ui` را
می‌پذیرد.

## به‌روزرسانی منبع متن

پس از تغییر `app_strings_snapshot.dart`، دستور زیر را اجرا کنید تا منبع زبان
با رابط Flutter همگام شود:

```bash
python scripts/extract_app_strings.py \
  --source app_strings_snapshot.dart \
  --out examples/base_strings.json
```

ترجمهٔ دستی یا بازتولید خودکار هر دو باید همهٔ کلیدها و placeholderهایی مانند
`{count}` و `{error}` را بدون تغییر نگه دارند؛ سازنده در غیر این صورت انتشار را
متوقف می‌کند.
