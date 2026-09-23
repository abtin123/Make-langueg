library;

/// اموجیِ پرچم از کدِ دوحرفیِ کشور (ISO 3166-1 alpha-2). پیشوندهای غیرحرفی
/// (زیرخط/عدد/پارت‌های چندپارتی مثل US-NE) نادیده گرفته می‌شوند تا پرچمِ
/// کشورهایی که id ساده‌ی دوحرفی ندارند هم درست ساخته شود.
String flagEmojiForCountryCode(String code) {
  final letters = RegExp(r'^[A-Za-z]{2}').stringMatch(code.trim());
  if (letters == null) return '🌐';
  const base = 0x1F1E6;
  final a = letters.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
  final b = letters.toUpperCase().codeUnitAt(1) - 'A'.codeUnitAt(0);
  if (a < 0 || a > 25 || b < 0 || b > 25) return '🌐';
  return String.fromCharCode(base + a) + String.fromCharCode(base + b);
}

/// نگاشتِ کدِ زبان (ISO 639-1) به کدِ کشورِ نماینده، فقط برای ساختِ پرچم در
/// بستهٔ صوتی (که کدِ زبان دارد نه کدِ کشور). زبان‌هایی که در این نگاشت
/// نیستند با فرضِ این‌که خودِ کد، کدِ کشور هم هست پردازش می‌شوند.
const Map<String, String> _languageToCountry = {
  'fa': 'IR',
  'en': 'GB',
  'ar': 'SA',
  'tr': 'TR',
  'ur': 'PK',
  'ku': 'IQ',
  'ps': 'AF',
  'ru': 'RU',
  'fr': 'FR',
  'de': 'DE',
  'es': 'ES',
  'it': 'IT',
  'zh': 'CN',
  'hi': 'IN',
  'az': 'AZ',
  'hy': 'AM',
  'ka': 'GE',
  'cs': 'CZ',
  'da': 'DK',
  'el': 'GR',
  'fi': 'FI',
  'he': 'IL',
  'hu': 'HU',
  'id': 'ID',
  'ja': 'JP',
  'ko': 'KR',
  'nl': 'NL',
  'no': 'NO',
  'pl': 'PL',
  'pt': 'PT',
  'ro': 'RO',
  'sv': 'SE',
  'th': 'TH',
  'uk': 'UA',
  'vi': 'VN',
};

String flagEmojiForLanguageCode(String code) {
  final normalized = code.trim().toLowerCase();
  if (normalized.isEmpty) return '🌐';
  final country = _languageToCountry[normalized] ?? normalized;
  return flagEmojiForCountryCode(country);
}

const Set<String> _bundledFlagCountries = {
  'ir',
  'gb',
  'sa',
  'de',
  'tr',
  'pk',
  'iq',
  'af',
  'ru',
  'fr',
  'es',
  'it',
  'cn',
  'in',
  'az',
  'am',
  'ge',
  'jp',
  'kr',
  'nl',
  'be',
  'dk',
  'se',
  'no',
  'fi',
  'pl',
  'pt',
  'ro',
  'ua',
  'gr',
  'il',
  'id',
  'vn',
  'th',
  'cz',
  'hu',
  'us',
};

/// مسیر asset واقعی پرچم با نسبت رسمی ۴:۳. فایل‌های SVG از مجموعهٔ استاندارد
/// flag-icons دریافت شده‌اند؛ برای کد ناشناخته، پرچم سازمان ملل (UN) نمایش
/// داده می‌شود تا هیچ‌گاه تصویر WebP بی‌کیفیت یا emoji ناهماهنگ به UI نرسد.
String flagAssetForCountryCode(String code) {
  final letters = RegExp(r'^[A-Za-z]{2}').stringMatch(code.trim());
  if (letters == null) return 'assets/images/flags/un.svg';
  final key = letters.toLowerCase();
  return _bundledFlagCountries.contains(key)
      ? 'assets/images/flags/$key.svg'
      : 'assets/images/flags/un.svg';
}

String flagAssetForLanguageCode(String code) {
  final normalized = code.trim().toLowerCase();
  if (normalized.isEmpty) return 'assets/images/flags/un.svg';
  final country = _languageToCountry[normalized] ?? normalized;
  return flagAssetForCountryCode(country);
}

/// حذفِ اضافاتِ کدِ زبان از یک برچسبِ نمایشی — چیزهایی مثل «فارسی (fa)»،
/// «English [en]»، «Turkish - tr» یا «فارسی_fa» که گاهی مستقیم از مانیفست
/// می‌آیند و تکراری/بی‌فایده‌اند چون خودِ برچسب یا پرچمِ کنارش همان اطلاعات
/// را می‌دهد.
String cleanLocalizedLabel(String raw) {
  var out = raw.trim();
  // «(fa)»، «[EN]»، «(fa-IR)» و مشابه، در هرجای رشته.
  out = out.replaceAll(
      RegExp(r'[\(\[]\s*[a-zA-Z]{2,3}(?:[-_][a-zA-Z]{2,4})?\s*[\)\]]'), '');
  // «- fa» یا «_ fa» در انتهای رشته (کدِ دو/سه‌حرفیِ تنها، جدا از بقیهٔ متن).
  out = out.replaceAll(RegExp(r'[\s\-_]+[a-zA-Z]{2,3}$'), '');
  return out.trim();
}
