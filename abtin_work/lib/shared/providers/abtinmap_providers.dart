import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../abtinmap/abm_map_service.dart';
import '../../features/offline_maps/data/map_catalog.dart';
import '../../features/offline_maps/data/vector_map_service.dart';
import '../../features/offline_maps/presentation/offline_maps_providers.dart';
import '../../features/routing/data/routing_provider.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/settings_repository_provider.dart';

/// سرویس دانلود و نگهداری فایل‌های .abm
final abmMapServiceProvider = Provider<AbmMapService>((ref) {
  final service = AbmMapService();
  ref.onDispose(service.closeMap);
  return service;
});

final vectorMapServiceProvider = Provider<VectorMapService>((ref) {
  return VectorMapService();
});

/// شناسهٔ دادهٔ آفلاین انتخاب‌شده؛ شامل Vector + map.sqlite (POI/Search/Routing) در ABM v4 است.
final activeOfflineMapIdProvider = StateProvider<String>((ref) => '');

/// نام فایل نقشه‌ی فعال (فعلاً ایران).
final abmActiveMapNameProvider = StateProvider<String>((ref) => '__none__.abm');

/// موتور پیش‌فرض نصب تازه آنلاین است؛ نمایش آغازین کرهٔ زمین از همین حالت
/// استفاده می‌کند و کاربر پس از دانلود نقشه می‌تواند آفلاین را انتخاب کند.
final routingEngineProvider =
    StateProvider<RoutingEngine>((ref) => RoutingEngine.online);

/// آفلاین فقط به فایل ABM واقعاً نصب‌شده و داده‌های داخل همان فایل وابسته است.
///
/// نکتهٔ مهم: این مسیر نباید به `MapCatalogService` یا اینترنت وابسته باشد.
/// مانیفست فقط برای فهرست/به‌روزرسانی دانلودهاست؛ بعد از دانلود، renderer باید
/// بتواند حتی با اینترنت کاملاً قطع، فایل محلی را باز کند. نسخهٔ قبلی اینجا
/// `mapCatalogProvider` را watch می‌کرد و اگر manifest گیت‌هاب در دسترس نبود،
/// `offlineAtlasReadyProvider` خطا می‌گرفت و HomeScreen دوباره OnlineMapView را
/// نشان می‌داد؛ در نتیجه نقشه روی دستگاه موجود بود ولی عملاً قابل انتخاب/نمایش
/// نبود.
Future<bool> hasActiveOfflineAtlas(dynamic ref) async {
  final service = ref.read(abmMapServiceProvider);
  var activeName = ref.read(abmActiveMapNameProvider).trim();
  // اگر فایل نقشه روی دستگاه نصب شده باشد اما کلید انتخابِ Active پاک شده
  // باشد، نسخهٔ قبلی همیشه false برمی‌گرداند. نتیجه این بود که دکمهٔ «آفلاین»
  // disabled می‌ماند و کاربر هیچ راهی برای انتخاب اولین نقشهٔ نصب‌شده نداشت.
  // در این حالت اولین فایل سالم نصب‌شده را به‌صورت خودکار به‌عنوان نقشهٔ
  // پیشنهادی انتخاب می‌کنیم؛ انتخاب نهایی موتور پایین‌تر انجام می‌شود.
  if (activeName.isEmpty || activeName == '__none__.abm') {
    final installed = await service.installedMaps();
    if (installed.isNotEmpty) {
      activeName = installed.first;
      ref.read(abmActiveMapNameProvider.notifier).state = activeName;
      final normalizedId = p.basenameWithoutExtension(activeName).toUpperCase();
      ref.read(activeOfflineMapIdProvider.notifier).state = normalizedId;
      await ref.read(settingsRepositoryProvider).setValue(
        SettingsRepository.keyActiveMapName,
        activeName,
      );
    }
  }
  // نام ذخیره‌شده را همان‌طور که دانلود شده امتحان می‌کنیم و سپس نسخهٔ نرمال
  // شده را. این کار برای دستگاه‌هایی که نسخهٔ قدیمی نام فایل را با حروف کوچک
  // ذخیره کرده‌اند نیز جلوی false-negative را می‌گیرد.
  final names = <String>{if (activeName.isNotEmpty && activeName != '__none__.abm') activeName};
  final id = activeName.toLowerCase().endsWith('.abm')
      ? activeName.substring(0, activeName.length - 4)
      : activeName;
  if (id.isNotEmpty) {
    names.add('$id.abm');
    names.add('${id.toUpperCase()}.abm');
  }

  File? file;
  for (final name in names) {
    final candidate = await service.localFile(name);
    if (await candidate.exists() && await candidate.length() > 0) {
      file = candidate;
      break;
    }
  }
  if (file == null) {
    
    return false;
  }

  // موقتاً اعتبارسنجی سخت‌گیرانهٔ ABM/Manifest/SQLite از مرحلهٔ انتخاب
  // موتور جدا شده است. قبلاً prepare() در همین نقطه فایل موجود را به‌خاطر
  // ناسازگاری یکی از اعضای داخلی یا cache رد می‌کرد و setRoutingEngine() آن
  // را بی‌صدا به Online برمی‌گرداند؛ در نتیجه کاربر فایل را می‌دید اما قادر
  // به فعال‌کردنش نبود. Renderer هنگام بازکردن فایل خطای واقعی را گزارش
  // می‌کند و بعداً می‌توان Validator را دوباره در مرحلهٔ نصب فعال کرد.
  return true;
}

Future<void> _setRoutingEngine(dynamic ref, RoutingEngine engine) async {
  if (engine == RoutingEngine.abtinmap) {
    var ready = await hasActiveOfflineAtlas(ref);
    if (!ready) {
      ref.read(routingEngineProvider.notifier).state = RoutingEngine.online;
      await ref.read(settingsRepositoryProvider).setValue(
        SettingsRepository.keyRoutingEngine, RoutingEngine.online.storageValue);
      return;
    }
  }
  ref.read(routingEngineProvider.notifier).state = engine;
  await ref.read(settingsRepositoryProvider).setValue(
    SettingsRepository.keyRoutingEngine, engine.storageValue);
}

/// Typed API for providers/controllers.
Future<void> setRoutingEngine(Ref ref, RoutingEngine engine) =>
    _setRoutingEngine(ref, engine);

/// Typed API for widget code.
Future<void> setRoutingEngineFromWidget(WidgetRef ref, RoutingEngine engine) =>
    _setRoutingEngine(ref, engine);


/// وضعیت واقعی آماده‌بودن فایل ABM فعال؛ بدون وابستگی به مانیفست آنلاین.
final offlineAtlasReadyProvider = FutureProvider<bool>((ref) async {
  return hasActiveOfflineAtlas(ref);
});

/// فایل ABM فعال برای Renderer. null یعنی فایل محلی پیدا نشده است.
final activeOfflineMapFileProvider = FutureProvider<File?>((ref) async {
  final service = ref.read(abmMapServiceProvider);
  final name = ref.watch(abmActiveMapNameProvider).trim();
  if (name.isEmpty || name == '__none__.abm') return null;
  final file = await service.localFile(name);
  if (!await file.exists() || await file.length() <= 0) return null;
  return file;
});

/// آیا نقشه‌ی .abm فعال روی دستگاه نصب است؟
final abmInstalledProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(abmMapServiceProvider);
  return service.isInstalled(ref.watch(abmActiveMapNameProvider));
});

/// نسخه‌ی نصب‌شده‌ی نقشه (از فایل کنار .abm).
final abmInstalledVersionProvider = FutureProvider<String?>((ref) async {
  final service = ref.watch(abmMapServiceProvider);
  return service.installedVersion(ref.watch(abmActiveMapNameProvider));
});

/// وضعیت دانلود نقشه‌ی .abm
class AbmDownloadState {
  const AbmDownloadState({
    this.busy = false,
    this.received = 0,
    this.total,
    this.error,
    this.done = false,
  });

  final bool busy;
  final int received;
  final int? total;
  final String? error;
  final bool done;

  double? get fraction =>
      (total == null || total == 0) ? null : received / total!;

  AbmDownloadState copyWith({
    bool? busy,
    int? received,
    int? total,
    String? error,
    bool? done,
  }) =>
      AbmDownloadState(
        busy: busy ?? this.busy,
        received: received ?? this.received,
        total: total ?? this.total,
        error: error,
        done: done ?? this.done,
      );
}

class AbmDownloadController extends StateNotifier<AbmDownloadState> {
  AbmDownloadController(this._ref) : super(const AbmDownloadState());

  final Ref _ref;

  Future<File?> download({bool force = false}) async {
    final service = _ref.read(abmMapServiceProvider);
    final name = _ref.read(abmActiveMapNameProvider);
    final id = name.toLowerCase().endsWith('.abm')
        ? name.substring(0, name.length - 4)
        : name;
    state = const AbmDownloadState(busy: true);
    try {
      final catalog = await _ref.read(mapCatalogServiceProvider).load();
      final region = catalog.byId(id) ?? catalog.byId(id.toUpperCase());
      final File file;
      if (region != null) {
        file = await service.downloadRegion(
          id: region.id,
          files: region.effectiveFiles,
          downloadBase: region.effectiveDownloadBase,
          totalSizeBytes: region.totalSizeBytes,
          expectedSha256: region.version,
          force: force,
          onProgress: (p) {
            state = state.copyWith(received: p.received, total: p.total);
          },
        );
      } else {
        // مانیفست در دسترس نبود؛ تلاش برای دانلود مستقیم با آدرس پیش‌فرض.
        file = await service.download(
          name,
          force: force,
          onProgress: (p) {
            state = state.copyWith(received: p.received, total: p.total);
          },
        );
      }
      state = state.copyWith(busy: false, done: true);
      _ref.invalidate(abmInstalledProvider);
      _ref.invalidate(abmInstalledVersionProvider);
      return file;
    } catch (error) {
      state = AbmDownloadState(
          busy: false, error: 'دانلود نقشه ناموفق بود: $error');
      return null;
    }
  }

  Future<void> delete() async {
    final service = _ref.read(abmMapServiceProvider);
    await service.deleteMap(_ref.read(abmActiveMapNameProvider));
    state = const AbmDownloadState();
    _ref.invalidate(abmInstalledProvider);
    _ref.invalidate(abmInstalledVersionProvider);
  }
}

final abmDownloadControllerProvider =
    StateNotifierProvider<AbmDownloadController, AbmDownloadState>(
        (ref) => AbmDownloadController(ref));

/// آیا نسخه‌ی جدیدتری از نقشه در manifest هست؟
final abmUpdateAvailableProvider = FutureProvider<bool>((ref) async {
  final name = ref.watch(abmActiveMapNameProvider);
  final id = name.toLowerCase().endsWith('.abm')
      ? name.substring(0, name.length - 4)
      : name;
  final service = ref.watch(abmMapServiceProvider);
  if (!await service.isInstalled(name)) return false;

  MapCatalog catalog;
  try {
    catalog = await ref.watch(mapCatalogServiceProvider).load();
  } catch (_) {
    return false;
  }
  final region = catalog.byId(id) ?? catalog.byId(id.toUpperCase());
  if (region == null || region.version.isEmpty) return false;
  final installed = await service.installedVersion(name);
  return installed != null && installed != region.version;
});
