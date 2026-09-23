import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';

import '../../core/localization/locale_flags.dart';
import '../offline_maps/data/map_catalog.dart';
import '../offline_maps/presentation/offline_maps_providers.dart';
import '../offline_maps/presentation/map_download_providers.dart';
import '../../shared/providers/abtinmap_providers.dart';
import '../../shared/providers/map_style_providers.dart';
import '../../shared/providers/app_settings_providers.dart';
import '../settings/presentation/settings_repository_provider.dart';
import '../settings/data/settings_repository.dart';
import '../routing/data/routing_provider.dart';
import 'language_hub_models.dart';

/// فهرست کشورها از همان MapCatalogService واقعی (کش‌شده، با فهرست پیش‌فرض
/// آفلاین به‌عنوان fallback) — نه یک منبع جدید.
final mapCatalogProvider = FutureProvider<MapCatalog>((ref) async {
  return ref.watch(mapCatalogServiceProvider).load();
});

/// آیتم‌های دانلود نقشه در صفحهٔ تنظیمات نقشه، به‌صورت [DownloadEntry]. هر
/// ردیف وضعیت دانلود/نصب مستقل خودش را از regionDownloadControllerProvider و
/// abmInstalledMapIdsProviderFamily می‌گیرد.
final mapDownloadEntriesProvider =
    Provider<AsyncValue<List<DownloadEntry>>>((ref) {
  final catalogAsync = ref.watch(mapCatalogProvider);
  final installedAsync = ref.watch(abmInstalledMapIdsProvider);
  final activeMap = ref.watch(abmActiveMapNameProvider);
  return catalogAsync.whenData((catalog) {
    final installed = installedAsync.value ?? const <String>{};
    return catalog.regions.map((region) {
      return DownloadEntry(
        id: region.id,
        title: region.name,
        subtitle: region.nameEn,
        sizeBytes: region.totalSizeBytes,
        installed: installed.contains(region.id),
        selected: activeMap == region.abmFileName,
        // وضعیت زندهٔ دانلود در کارت‌های صفحهٔ دانلود جداگانه watch می‌شود؛
        // این provider خلاصه نباید برای صدها کشور controller بسازد.
        progress: null,
        error: null,
        flag: flagAssetForCountryCode(region.effectiveCountryCode),
      );
    }).toList(growable: false);
  });
});

Future<void> downloadMapRegion(WidgetRef ref, MapRegion region) async {
  await ref.read(regionDownloadControllerProvider(region).notifier).start();
}

Future<void> activateMapRegion(WidgetRef ref, MapRegion region) async {
  // انتخاب نقشه باید همان مسیر فعال‌سازیِ صفحهٔ دانلود را طی کند. قبلاً این
  // helper فقط active_map_name را می‌نوشت؛ بنابراین کارت «دانلود شده» فعال
  // به نظر می‌رسید ولی activeOfflineMapId و موتور routing همچنان روی حالت
  // قبلی می‌ماندند و HomeScreen نقشهٔ آفلاین را وارد نمی‌کرد.
  ref.read(abmActiveMapNameProvider.notifier).state = region.abmFileName;
  ref.read(activeOfflineMapIdProvider.notifier).state = region.id;
  await ref
      .read(settingsRepositoryProvider)
      .setValue(SettingsRepository.keyActiveMapName, region.abmFileName);
  await setRoutingEngineFromWidget(ref, RoutingEngine.abtinmap);
  ref.invalidate(offlineAtlasReadyProvider);
  ref.invalidate(resolvedMapStyleProvider);
}

/// زبان رابط برنامه را تغییر می‌دهد و در تنظیمات ذخیره می‌کند. صفحهٔ زبان
/// (LanguageHubScreen) این تابع را هم برای فارسی/انگلیسیِ همراه اپ و هم
/// برای زبان‌های دانلودشده صدا می‌زند.
Future<void> selectAppLanguage(WidgetRef ref, String code) async {
  if (AppStrings.supportedBundledLanguageCodes.contains(code) && code != 'fa') {
    await AppStrings.loadBundledLanguage(code);
  }
  ref.read(languageProvider.notifier).state = code;
  await ref
      .read(settingsRepositoryProvider)
      .setValue(SettingsRepository.keyLanguage, code);
}
