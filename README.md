# آبتین‌مپ — سازنده بسته‌های زبان

این پروژه **فقط از JSONهای موجود در `locales/`** بسته‌های زبان را می‌سازد.

## قانون اصلی

- هیچ فایل Dart خوانده یا لازم نیست.
- هیچ `app_strings_snapshot.dart` وجود یا وابستگی ندارد.
- هیچ API Key، OpenAI یا سرویس ترجمه‌ای لازم نیست.
- هیچ کلیدی ساخته، اضافه، حذف یا به‌روزرسانی نمی‌شود.
- `locales/fa.json` فقط به‌عنوان **مرجع کلیدهای موجود** استفاده می‌شود.
- متن ترجمه‌ها دقیقاً از JSONهای موجود هر زبان خوانده می‌شود.
- اگر کلید یک زبان با `fa.json` فرق داشته باشد، Build متوقف می‌شود.
- اگر مقدار خالی باشد، Build متوقف می‌شود.

## ساخت

```bash
python tests/validate_language_pack_contract.py --require-complete
python scripts/build.py   --locales-dir locales   --out out   --download-base "https://github.com/OWNER/REPOSITORY/releases/download/langpacks-latest"
```

Workflow گیت‌هاب نیز دقیقاً همین مسیر را اجرا می‌کند: اعتبارسنجی JSONهای موجود، سپس ساخت بسته‌ها و انتشار Release.

برای اضافه‌کردن یا تغییر متن، خود فایل‌های JSON داخل `locales/` باید مستقیماً ویرایش شوند؛ سازنده هیچ تغییری در کلیدها ایجاد نمی‌کند.
