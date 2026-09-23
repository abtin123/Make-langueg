import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/language_pack_catalog.dart';
import '../data/language_pack_service.dart';

final languagePackServiceProvider = Provider<LanguagePackService>((ref) {
  return LanguagePackService();
});

/// شمارندهٔ تازه‌سازی دستیِ فهرست زبان‌ها (دکمهٔ «تازه‌سازی» در صفحهٔ زبان).
/// فقط با تغییر همین مقدار، مانیفست بدون توجه به کشِ محلی دوباره از شبکه
/// خوانده می‌شود؛ ورود/خروج از صفحه به‌تنهایی هرگز این کار را نمی‌کند.
final languagePackCatalogRefreshProvider = StateProvider<int>((ref) => 0);

/// فهرست زبان‌های دانلودی از مانیفستِ Make-langueg (جایگزینِ لیستِ ثابتِ
/// قبلی downloadableLanguages).
final languagePackManifestProvider =
    FutureProvider<List<LanguagePack>>((ref) async {
  final refreshCount = ref.watch(languagePackCatalogRefreshProvider);
  return ref
      .watch(languagePackServiceProvider)
      .fetchManifest(forceRefresh: refreshCount > 0);
});

/// کدهای زبان‌هایی که همین الان روی دستگاه دانلود شده‌اند (خالی تا اولین
/// بار [loadAllDownloaded] در startup اجرا شود).
final downloadedLanguagesProvider =
    StateNotifierProvider<DownloadedLanguagesNotifier, Set<String>>((ref) {
  return DownloadedLanguagesNotifier(ref.watch(languagePackServiceProvider));
});

class DownloadedLanguagesNotifier extends StateNotifier<Set<String>> {
  DownloadedLanguagesNotifier(this._service) : super(const {});
  final LanguagePackService _service;

  Future<void> loadFromDisk() async {
    state = await _service.loadAllDownloaded();
  }

  /// مثل [loadFromDisk] اما نتیجه را هم برمی‌گرداند — برای استفاده در
  /// [appSettingsInitProvider] که همان لحظه به لیست زبان‌های دانلودشده
  /// نیاز دارد (تا بداند آیا زبانِ ذخیره‌شده‌ی کاربر معتبر است یا نه).
  Future<Set<String>> loadFromDiskAndReturn() async {
    await loadFromDisk();
    return state;
  }

  Future<void> markDownloaded(String code) async {
    state = {...state, code};
  }

  Future<void> markRemoved(String code) async {
    state = {...state}..remove(code);
  }
}

/// پیشرفتِ دانلودِ در حال انجام برای هر کد زبان (۰ تا ۱)؛ اگر زبانی در حال
/// دانلود نباشد، مقداری در این مپ ندارد.
final languageDownloadProgressProvider =
    StateProvider<Map<String, LanguageDownloadProgress>>((ref) => {});

/// خطای آخرین تلاش دانلود برای هر کد زبان (برای نمایش پیام خطا در UI).
final languageDownloadErrorProvider =
    StateProvider<Map<String, String>>((ref) => {});

/// دانلود یک بسته‌ی زبان را شروع می‌کند و پیشرفت/نتیجه را در providerهای بالا
/// به‌روزرسانی می‌کند. صفحه فقط این تابع را صدا می‌زند؛ نیازی به مدیریت
/// دستیِ progress ندارد.
Future<void> downloadLanguagePack(WidgetRef ref, LanguagePack pack) async {
  final service = ref.read(languagePackServiceProvider);
  ref.read(languageDownloadErrorProvider.notifier).update(
        (m) => {...m}..remove(pack.code),
      );
  try {
    final pending = await service.pendingProgress(pack);
    ref.read(languageDownloadProgressProvider.notifier).update(
          (m) => {...m, pack.code: pending},
        );
    await service.download(
      pack,
      onProgress: (p) {
        ref.read(languageDownloadProgressProvider.notifier).update(
              (m) => {...m, pack.code: p},
            );
      },
    );
    await ref
        .read(downloadedLanguagesProvider.notifier)
        .markDownloaded(pack.code);
    // خطای قبلیِ همین زبان نباید بعد از نصب موفق روی کارت باقی بماند.
    ref.read(languageDownloadErrorProvider.notifier).update(
          (m) => {...m}..remove(pack.code),
        );
  } catch (e) {
    ref.read(languageDownloadErrorProvider.notifier).update(
          (m) => {...m, pack.code: e.toString()},
        );
  } finally {
    ref.read(languageDownloadProgressProvider.notifier).update(
          (m) => {...m}..remove(pack.code),
        );
  }
}

/// حذف بسته‌ی زبانِ دانلودشده از دیسک.
Future<void> deleteLanguagePack(WidgetRef ref, LanguagePack pack) async {
  final service = ref.read(languagePackServiceProvider);
  await service.delete(pack);
  await ref.read(downloadedLanguagesProvider.notifier).markRemoved(pack.code);
}
