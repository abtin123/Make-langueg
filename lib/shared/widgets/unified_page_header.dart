import 'page_header.dart';

/// نام قدیمی هدر برای سازگاری با صفحه‌هایی که قبلاً از آن استفاده می‌کردند.
/// پیاده‌سازی واقعی اکنون همان [PageHeader] مشترک است.
class UnifiedPageHeader extends PageHeader {
  const UnifiedPageHeader({
    super.key,
    required super.title,
    super.onRefresh,
    super.backRoute,
    super.actions,
  });
}
