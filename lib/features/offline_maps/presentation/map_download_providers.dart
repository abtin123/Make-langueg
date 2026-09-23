import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../abtinmap/abm_map_service.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../../shared/providers/map_style_providers.dart';
import '../data/map_catalog.dart';
import '../data/vector_map_service.dart';
import '../../routing/data/routing_provider.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import 'offline_maps_providers.dart';

/// وضعیت دانلود مستقل هر کشور (برخلاف [AbmDownloadController] که فقط یک
/// نقشه‌ی «فعال» را مدیریت می‌کند، اینجا هر [MapRegion] وضعیت جدای خودش را
/// دارد تا چند کارت هم‌زمان بتوانند در حال دانلود/توقف/نصب باشند).
enum RegionDownloadPhase { downloading, building, saving, completed }

class RegionDownloadState {
  const RegionDownloadState({
    this.downloading = false,
    this.received = 0,
    this.total,
    this.phase,
    this.error,
  });

  final bool downloading;
  final RegionDownloadPhase? phase;
  final int received;
  final int? total;
  final String? error;

  double? get fraction =>
      (total == null || total == 0) ? null : (received / total!).clamp(0, 1);

  RegionDownloadState copyWith({
    bool? downloading,
    int? received,
    int? total,
    RegionDownloadPhase? phase,
    String? error,
  }) =>
      RegionDownloadState(
        downloading: downloading ?? this.downloading,
        received: received ?? this.received,
        total: total ?? this.total,
        phase: phase ?? this.phase,
        error: error,
      );
}

class RegionDownloadController extends StateNotifier<RegionDownloadState> {
  RegionDownloadController(this._ref, this._region)
      : super(const RegionDownloadState());

  final Ref _ref;
  final MapRegion _region;
  bool _cancelled = false;

  /// این پروایدر `autoDispose` است: با خروج از صفحهٔ دانلود (مثلاً برگشتن به
  /// تنظیمات)، به‌محض این‌که هیچ ویجتی دیگر آن را `watch` نکند، ریوِرپاد
  /// بلافاصله `StateNotifier` را `dispose` می‌کند. اما دانلود شبکه‌ای در پس‌زمینه
  /// (داخل `AbmMapService`, که خودش `autoDispose` نیست) هم‌چنان ادامه دارد و
  /// در هر chunk سعی می‌کند `state` را به‌روزرسانی کند؛ نوشتن روی یک
  /// StateNotifier از بین‌رفته خطا پرتاب می‌کند و کل دانلود را وسط راه با
  /// استثنا متوقف می‌کند — همان چیزی که باعث می‌شد کاربر با برگشتن به صفحه
  /// دوباره «نصب‌نشده» ببیند و مجبور به دانلود از نو شود.
  ///
  /// راه‌حل: تا پایان دانلود (موفق/خطا/لغو) با `ref.keepAlive()` از حذف
  /// زودهنگام این پروایدر جلوگیری می‌کنیم؛ و برای اطمینان بیشتر پیش از هر
  /// تغییر state هم [mounted] را چک می‌کنیم.
  KeepAliveLink? _keepAliveLink;

  Future<void> start() async {
    if (state.downloading) return;
    _cancelled = false;
    state = const RegionDownloadState(
      downloading: true,
      phase: RegionDownloadPhase.downloading,
    );
    _keepAliveLink ??= _ref.keepAlive();
    final service = _ref.read(abmMapServiceProvider);
    var activeRegion = _region;
    final vector = _region.vectorMap;
    final vectorService = _ref.read(vectorMapServiceProvider);
    try {
      final onProgress = (AbmDownloadProgress p) {
        if (_cancelled || !mounted) return;
        state = state.copyWith(
          received: p.received,
          total: activeRegion.totalSizeBytes > 0
              ? activeRegion.totalSizeBytes
              : p.total,
        );
      };
      Future<void> downloadRegionFor(MapRegion region) async {
        if (region.isBundledAsset) {
          await service.installBundledAsset(
            name: region.abmFileName,
            assetPath: region.bundledAsset,
            version: region.version,
            onProgress: onProgress,
          );
        } else {
          await service.downloadRegion(
            id: region.id,
            files: region.effectiveFiles,
            patch: region.patch,
            downloadBase: region.effectiveDownloadBase,
            totalSizeBytes: region.totalSizeBytes,
            expectedSha256: region.version,
            onProgress: onProgress,
            isCancelled: () => _cancelled,
          );
        }
      }

      try {
        await downloadRegionFor(activeRegion);
      } on AbmFormatException catch (error) {
        // maps-v4 is a mutable GitHub release. The catalog is cached for a day,
        // so a release asset can legitimately be newer than the SHA cached on
        // the device. A SHA mismatch must never be treated as a bad network
        // transfer forever: refresh the release manifest once and retry with
        // the exact checksum/size of the current asset.
        final text = error.toString();
        final integrityFailure = text.contains('ناقص') ||
            text.contains('خراب') ||
            text.contains('نامعتبر');
        if (!integrityFailure || _cancelled) rethrow;

        try {
          final freshCatalog = await _ref
              .read(mapCatalogServiceProvider)
              .load(forceRefresh: true);
          final freshRegion = freshCatalog.byId(_region.id);
          if (freshRegion == null || freshRegion.version == _region.version) {
            rethrow;
          }
          activeRegion = freshRegion;
          
          await downloadRegionFor(activeRegion);
        } catch (_) {
          rethrow;
        }
      }
      if (_cancelled) throw const AbmDownloadCancelled();
      final containerFile = await service.localFile(activeRegion.abmFileName);
      if (mounted) {
        state = state.copyWith(
          phase: RegionDownloadPhase.building,
          // Download is already complete. Do not reset the progress bar to 0:
          // opening/validating the ABM is metadata-only and must not look like
          // a long second download/install stage.
          received: activeRegion.totalSizeBytes,
          total: activeRegion.totalSizeBytes,
        );
      }
      await vectorService.prepare(
        containerFile: containerFile,
        id: _region.id,
        onProgress: (v) {
          if (!mounted || _cancelled) return;
          // prepare() only validates metadata and creates tiny readiness
          // markers; it is not a country-wide build step. Keep download at
          // 100% while this short final validation runs.
          state = state.copyWith(
            received: activeRegion.totalSizeBytes,
            total: activeRegion.totalSizeBytes,
          );
        },
      );
      if (mounted) {
        state = state.copyWith(
          phase: RegionDownloadPhase.saving,
          received: activeRegion.totalSizeBytes,
          total: activeRegion.totalSizeBytes,
        );
      }
      // prepare() already opened and fully validated the ABM contract and
      // wrote the readiness markers. Do not reopen the ZIP here: doing so
      // parses the central directory a second time and made the post-download
      // "install" phase look unnecessarily long on large maps.
      if (!mounted) return;
      if (_cancelled) {
        state = const RegionDownloadState();
        return;
      }
      if (mounted) {
        state = RegionDownloadState(
          downloading: false,
          received:
              activeRegion.totalSizeBytes > 0 ? activeRegion.totalSizeBytes : 1,
          total:
              activeRegion.totalSizeBytes > 0 ? activeRegion.totalSizeBytes : 1,
          phase: RegionDownloadPhase.completed,
        );
      }
      // فعال‌سازی مستقیم پس از دانلود؛ اعتبارسنجی ساختار ABM در این مرحله انجام نمی‌شود.
      _ref.read(abmActiveMapNameProvider.notifier).state =
          activeRegion.abmFileName;
      _ref.read(activeOfflineMapIdProvider.notifier).state = activeRegion.id;
      // دانلود موفق باید همان لحظه نقشه را قابل انتخاب و واقعاً فعال کند؛
      // صرفاً عوض‌کردن نام فایل کافی نیست، چون routingEngineProvider هنوز
      // روی online می‌ماند و دکمهٔ «آفلاین» نیز disabled دیده می‌شود.
      await setRoutingEngine(_ref, RoutingEngine.abtinmap);
      await _ref.read(settingsRepositoryProvider).setValue(
            SettingsRepository.keyActiveMapName,
            activeRegion.abmFileName,
          );
      _ref.invalidate(abmInstalledMapIdsProviderFamily(activeRegion.id));
      _ref.invalidate(abmInstalledProvider);
      _ref.invalidate(abmInstalledVersionProvider);
      _ref.invalidate(offlineAtlasReadyProvider);
      _ref.invalidate(resolvedMapStyleProvider);
    } on AbmDownloadCancelled {
      if (mounted) state = const RegionDownloadState();
    } catch (error, stack) {
      
      if (mounted) state = RegionDownloadState(error: '$error');
    } finally {
      _keepAliveLink?.close();
      _keepAliveLink = null;
    }
  }

  /// دانلودِ در حال اجرا را بلافاصله (وسط دریافت chunk فعلی) لغو می‌کند.
  /// چون بخشِ نیمه‌دانلودشده روی دیسک (`*.part`) نگه داشته می‌شود و سرور از
  /// هدر `Range` پشتیبانی می‌کند، دفعه‌ی بعد که «شروع» زده شود دانلود از همان
  /// نقطه ادامه پیدا می‌کند — نه از صفر؛ در عمل همان تجربه‌ی «مکث و ادامه».
  void pause() {
    _cancelled = true;
  }

  Future<void> delete() async {
    final service = _ref.read(abmMapServiceProvider);
    await service.deleteMap(_region.abmFileName);
    await _ref.read(vectorMapServiceProvider).delete(_region.id);
    state = const RegionDownloadState();
    _ref.invalidate(abmInstalledMapIdsProviderFamily(_region.id));
    _ref.invalidate(abmInstalledProvider);
    _ref.invalidate(abmInstalledVersionProvider);
    // اگر همین نقشه فعال بود، providerهای داده نیز باید invalidate شوند تا
    // routing و search به فایل حذف‌شده اشاره نکنند.
    if (_ref.read(abmActiveMapNameProvider) == _region.abmFileName) {
      _ref.read(abmActiveMapNameProvider.notifier).state = '__none__.abm';
      _ref.read(activeOfflineMapIdProvider.notifier).state = '';
      await setRoutingEngine(_ref, RoutingEngine.online);
    }
    _ref.invalidate(offlineAtlasReadyProvider);
    _ref.invalidate(resolvedMapStyleProvider);
  }
}

final regionDownloadControllerProvider = StateNotifierProvider.family
    .autoDispose<RegionDownloadController, RegionDownloadState, MapRegion>(
        (ref, region) => RegionDownloadController(ref, region));

/// آیا نقشه‌ی این کشور مشخص روی دستگاه نصب است؟ (خانواده‌ی سبک برای
/// invalidation دقیق به‌جای رفرش کل لیست).
final abmInstalledMapIdsProviderFamily =
    FutureProvider.family.autoDispose<bool, String>((ref, regionId) async {
  final service = ref.watch(abmMapServiceProvider);
  return service.isInstalled('$regionId.abm');
});
