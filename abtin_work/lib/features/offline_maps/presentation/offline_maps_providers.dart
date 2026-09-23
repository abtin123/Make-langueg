import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../data/map_catalog.dart';
import '../../../shared/providers/abtinmap_providers.dart';

final mapCatalogServiceProvider = Provider<MapCatalogService>((ref) {
  final service = MapCatalogService();
  ref.onDispose(service.dispose);
  return service;
});

/// شمارندهٔ تازه‌سازی دستی فهرست کشورها (دکمهٔ «بررسی به‌روزرسانی»).
final catalogRefreshProvider = StateProvider<int>((ref) => 0);

/// فهرست کشورهای قابل دانلود؛ از مانیفست ریلیز، با کش آفلاین.
final mapCatalogProvider = FutureProvider<MapCatalog>((ref) async {
  final refreshCount = ref.watch(catalogRefreshProvider);
  final catalog = await ref
      .watch(mapCatalogServiceProvider)
      .load(forceRefresh: refreshCount > 0);
  return catalog;
});

/// نقشه‌هایی که واقعاً روی دستگاه نصب‌اند — مستقیم از دیسک، نه از مانیفست.
///
/// قبلاً تب «دانلودشده‌ها» صرفاً فیلتری روی [mapCatalogProvider] بود: اگر
/// مانیفست آنلاین لود نمی‌شد (اینترنت قطع، گیت‌هاب فیلتر، ۴۰۴ موقت و...)
/// کل صفحه با خطا/Retry جایگزین می‌شد و نقشه‌های واقعاً نصب‌شده روی گوشی هم
/// دیگر قابل دیدن/انتخاب نبودند. این provider مستقل از شبکه، پوشهٔ نقشه‌ها
/// را می‌خواند و برای هر فایل `.abm`، ردیف متناظرش را (اگر مانیفست در
/// دسترس بود) از کاتالوگ می‌گیرد؛ در غیر این صورت یک [MapRegion] حداقلی از
/// روی خودِ فایل می‌سازد تا نقشه هرگز از تب «دانلودشده‌ها» ناپدید نشود.
final installedMapRegionsProvider =
    FutureProvider.autoDispose<List<MapRegion>>((ref) async {
  final mapService = ref.watch(abmMapServiceProvider);
  final installedNames = await mapService.installedMaps();
  if (installedNames.isEmpty) return const <MapRegion>[];

  MapCatalog? catalog;
  try {
    catalog = await ref.watch(mapCatalogServiceProvider).load();
  } catch (_) {
    // مانیفست در دسترس نیست؛ فقط از دیسک ادامه می‌دهیم.
    catalog = null;
  }

  final regions = <MapRegion>[];
  for (final fileName in installedNames) {
    final id = p
        .basenameWithoutExtension(fileName)
        .toUpperCase();
    final fromCatalog = catalog?.byId(id);
    if (fromCatalog != null) {
      regions.add(fromCatalog);
      continue;
    }
    int sizeBytes = 0;
    try {
      sizeBytes = await (await mapService.localFile(fileName)).length();
    } catch (_) {}
    regions.add(MapRegion.fromInstalledFileOnly(
      id: id,
      fileSizeBytes: sizeBytes,
    ));
  }
  return regions;
});

/// شناسهٔ (id) بسته‌هایی که فایل .abm‌شان واقعاً روی دستگاه نصب است — همان
/// چیزی که نقشهٔ اصلی (رندر آبتین) واقعاً از آن می‌خواند.
final abmInstalledMapIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final service = ref.watch(abmMapServiceProvider);
  final names = await service.installedMaps();
  return names.map((n) => p.basenameWithoutExtension(n)).toSet();
});

/// نقشه‌هایی که نسخهٔ جدیدتری در مانیفست دارند (بر اساس نسخهٔ فایل .abm نصب‌شده).
final updatableMapIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final catalog = await ref.watch(mapCatalogProvider.future);
  final service = ref.watch(abmMapServiceProvider);
  final out = <String>{};
  for (final region in catalog.regions) {
    final installed = await service.installedVersion(region.abmFileName);
    if (installed != null && installed != region.version) {
      out.add(region.id);
    }
  }
  return out;
});
