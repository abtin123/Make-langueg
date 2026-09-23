import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/app_settings_providers.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../../shared/providers/map_style_providers.dart';
import '../../routing/data/routing_provider.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../data/map_catalog.dart';
import '../data/vector_map_service.dart';
import 'map_download_providers.dart';
import 'offline_maps_providers.dart';

/// صفحه‌ی «دانلود نقشه». طراحی مطابق نمونه‌ی مرجع: کارت‌های مستقل برای هر
/// کشور با نوار پیشرفت، دکمه‌های دانلود/توقف/به‌روزرسانی/حذف، و بخش پایانی
/// فقط برای فضای دستگاه (بدون تفکیک حجم نقشه‌ها). همه‌ی رنگ‌ها از
/// [AppColors] (یعنی از ColorScheme فعلی برنامه) خوانده می‌شوند تا با
/// انتخاب تم رنگی کاربر هماهنگ بمانند.
class DownloadMapScreen extends ConsumerStatefulWidget {
  const DownloadMapScreen({super.key});

  @override
  ConsumerState<DownloadMapScreen> createState() => _DownloadMapScreenState();
}

enum _MapMode { online, offline }

enum _MapDownloadTab { downloaded, notDownloaded }

class _DownloadMapScreenState extends ConsumerState<DownloadMapScreen> {
  _MapDownloadTab _tab = _MapDownloadTab.notDownloaded;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = ref.watch(languageProvider) == 'en';

    // تب «دانلودشده‌ها» فقط به دیسک وابسته است و نباید با خطای مانیفست
    // آنلاین مسدود شود؛ تب «دانلود نشده‌ها» ذاتاً به فهرست آنلاین نیاز دارد.
    if (_tab == _MapDownloadTab.downloaded) {
      final installedAsync = ref.watch(installedMapRegionsProvider);
      return Scaffold(
        backgroundColor: AppColors.background(context),
        appBar: PageHeader(
          title: AppStrings.get(context, ref, 'download_map_title'),
          backRoute: '/settings',
        ),
        body: SafeArea(
          top: false,
          child: installedAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorState(
              message: '$error',
              retryLabel: AppStrings.get(context, ref, 'downloads_retry'),
              onRetry: () => ref.invalidate(installedMapRegionsProvider),
            ),
            data: (regions) => _buildBody(context, regions, isEnglish),
          ),
        ),
      );
    }

    final catalogAsync = ref.watch(mapCatalogProvider);
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
        title: AppStrings.get(context, ref, 'download_map_title'),
        backRoute: '/settings',
      ),
      body: SafeArea(
        top: false,
        child: catalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: '$error',
            retryLabel: AppStrings.get(context, ref, 'downloads_retry'),
            onRetry: () => ref.read(catalogRefreshProvider.notifier).state++,
          ),
          data: (catalog) => _buildBody(context, catalog.regions, isEnglish),
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, List<MapRegion> regions, bool isEnglish) {
    // در تب «دانلودشده‌ها»، regions از قبل همان فهرست نصب‌شدهٔ دیسک است؛
    // فیلترِ installedIds اینجا لازم نیست و — مهم‌تر — نباید نقشه‌ای را که
    // در مانیفست نیست (پس در abmInstalledMapIdsProvider هم شرکت نمی‌کند)
    // به‌اشتباه حذف کند.
    final filtered = _tab == _MapDownloadTab.downloaded
        ? regions.where((r) => r.matches(_query)).toList()
        : (() {
            final installedIds = ref.watch(abmInstalledMapIdsProvider).valueOrNull ??
                const <String>{};
            return regions
                .where((r) => r.matches(_query))
                .where((r) => !installedIds.contains(r.id))
                .toList();
          })();
    filtered.sort((a, b) =>
        (isEnglish ? a.nameEn : a.name).compareTo(isEnglish ? b.nameEn : b.name));
    final grouped = <String, List<MapRegion>>{};
    for (final region in filtered) {
      grouped.putIfAbsent(region.effectiveCountryCode, () => []).add(region);
    }
    final groupKeys = grouped.keys.toList()
      ..sort((a, b) {
        final left = grouped[a]!.first.displayCountryName(isEnglish);
        final right = grouped[b]!.first.displayCountryName(isEnglish);
        return left.compareTo(right);
      });
    // فقط widgetهای سبک ساخته می‌شوند؛ ساخت و build کارت‌ها به اسکرول واگذار
    // می‌شود تا ۱۶۴ کشور هم‌زمان درخت سنگینِ قابل‌رندر نسازند.
    final listChildren = <Widget>[
      Text(
        AppStrings.get(context, ref, 'download_map_subtitle'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13.5,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.primaryAccent(context).withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          AppStrings.literal('نقشه و مسیریابی فقط آفلاین هستند.'),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 14),
      _DownloadTabs(
        selected: _tab,
        downloadedLabel: AppStrings.get(context, ref, 'downloaded_ones'),
        notDownloadedLabel: AppStrings.get(context, ref, 'not_downloaded_ones'),
        onChanged: (value) => setState(() => _tab = value),
      ),
      const SizedBox(height: 14),
      _SearchRow(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        onRefresh: () => ref.read(catalogRefreshProvider.notifier).state++,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Icon(Icons.public_rounded,
              size: 18, color: AppColors.primaryAccent(context)),
          const SizedBox(width: 6),
          Text(
            AppStrings.getWithParams(
              context,
              ref,
              'all_countries_count',
              {'count': filtered.length},
            ),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];
    for (final key in groupKeys) {
      final items = grouped[key]!
        ..sort((a, b) {
          final order = a.groupOrder.compareTo(b.groupOrder);
          return order != 0
              ? order
              : a
                  .displayRegionName(isEnglish)
                  .compareTo(b.displayRegionName(isEnglish));
        });
      final isRegional = items.length > 1 || items.first.isRegionalPackage;
      if (isRegional) {
        listChildren
          ..add(_CountryGroupHeader(region: items.first, count: items.length))
          ..add(const SizedBox(height: 8));
      }
      for (final region in items) {
        listChildren
          ..add(_RegionCard(region: region))
          ..add(const SizedBox(height: 12));
      }
    }
    listChildren.add(const SizedBox(height: 8));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: listChildren.length,
      itemBuilder: (_, index) => listChildren[index],
    );
  }
}

class _ModeToggle extends ConsumerWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _MapMode mode;
  final ValueChanged<_MapMode> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            selected: mode == _MapMode.online,
            icon: Icons.cloud_outlined,
            title: AppStrings.get(context, ref, 'map_mode_online'),
            subtitle: AppStrings.get(context, ref, 'map_mode_online_desc'),
            onTap: () => onChanged(_MapMode.online),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeCard(
            selected: mode == _MapMode.offline,
            icon: Icons.check_circle_rounded,
            title: AppStrings.get(context, ref, 'map_mode_offline'),
            subtitle: AppStrings.get(context, ref, 'map_mode_offline_desc'),
            onTap: () => onChanged(_MapMode.offline),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? accent.withOpacity(0.14)
                : AppColors.glassPanelSoft(context),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.85)
                  : AppColors.glassBorder(context),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.28),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? accent : AppColors.textSecondary(context),
                  size: 24),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted(context),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadTabs extends StatelessWidget {
  const _DownloadTabs({
    required this.selected,
    required this.downloadedLabel,
    required this.notDownloadedLabel,
    required this.onChanged,
  });

  final _MapDownloadTab selected;
  final String downloadedLabel;
  final String notDownloadedLabel;
  final ValueChanged<_MapDownloadTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassPanelSoft(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DownloadTabButton(
              label: downloadedLabel,
              selected: selected == _MapDownloadTab.downloaded,
              accent: accent,
              onTap: () => onChanged(_MapDownloadTab.downloaded),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _DownloadTabButton(
              label: notDownloadedLabel,
              selected: selected == _MapDownloadTab.notDownloaded,
              accent: accent,
              onTap: () => onChanged(_MapDownloadTab.notDownloaded),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTabButton extends StatelessWidget {
  const _DownloadTabButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                color: AppColors.glassPanelSoft(context),
                border: Border.all(color: AppColors.glassBorder(context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 19, color: AppColors.textMuted(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText:
                            AppStrings.get(context, ref, 'search_country_hint'),
                        hintStyle:
                            TextStyle(color: AppColors.textMuted(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _CircleIconButton(
            icon: Icons.refresh_rounded,
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(23),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.glassPanelSoft(context),
            border: Border.all(color: AppColors.glassBorder(context)),
          ),
          child: Icon(icon, size: 19, color: AppColors.textSecondary(context)),
        ),
      ),
    );
  }
}

class _CountryGroupHeader extends ConsumerWidget {
  const _CountryGroupHeader({required this.region, required this.count});

  final MapRegion region;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnglish = ref.watch(languageProvider) == 'en';
    final label = region.displayCountryName(isEnglish);
    return Row(
      children: [
        _FlagBadge(countryCode: region.effectiveCountryCode, glow: false),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          isEnglish ? '$count regions' : '$count بخش',
          style: TextStyle(
            color: AppColors.textMuted(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RegionCard extends ConsumerWidget {
  const _RegionCard({required this.region});

  final MapRegion region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final download = ref.watch(regionDownloadControllerProvider(region));
    final installedAsync =
        ref.watch(abmInstalledMapIdsProviderFamily(region.id));
    final updatableAsync = ref.watch(updatableMapIdsProvider);
    final installed = installedAsync.valueOrNull ?? false;
    final activeMapName = ref.watch(abmActiveMapNameProvider);
    final routingEngine = ref.watch(routingEngineProvider);
    final offlineReady =
        ref.watch(offlineAtlasReadyProvider).valueOrNull ?? false;
    // «فعال» فقط وقتی نشان داده شود که موتور واقعاً روی ABM باشد و همان
    // فایل نیز معتبر شناخته شده باشد. قبلاً صرفاً تطبیق نام فایل باعث می‌شد
    // کارت سبز «فعال» نشان داده شود در حالی که Home هنوز OnlineMapView بود.
    final isActive = installed &&
        activeMapName.toLowerCase() == region.abmFileName.toLowerCase() &&
        routingEngine == RoutingEngine.abtinmap &&
        offlineReady;
    final isUpdatable =
        updatableAsync.valueOrNull?.contains(region.id) ?? false;
    final controller =
        ref.read(regionDownloadControllerProvider(region).notifier);
    // باگ: اسمِ کشور همیشه فارسی (region.name) نشان داده می‌شد، حتی در
    // زبانِ انگلیسی؛ region.nameEn هیچ‌جا استفاده نمی‌شد.
    final isEnglish = ref.watch(languageProvider) == 'en';
    final displayName = region.displayRegionName(isEnglish);

    final bool isDownloading = download.downloading;
    final double? fraction = download.fraction;
    final phase = download.phase;
    final double receivedMb = download.received / (1024 * 1024);
    final double totalMb =
        (download.total ?? region.totalSizeBytes) / (1024 * 1024);

    final Color progressColor = isDownloading
        ? AppColors.primaryAccent(context)
        : installed
            ? const Color(0xFF3DDC84)
            : AppColors.textMuted(context).withOpacity(0.3);

    String statusText;
    if (isDownloading && phase == RegionDownloadPhase.downloading) {
      statusText = 'در حال دانلود نقشه…';
    } else if (isDownloading && phase == RegionDownloadPhase.building) {
      statusText = 'در حال ساخت نقشه آفلاین و ایندکس‌ها…';
    } else if (isDownloading && phase == RegionDownloadPhase.saving) {
      statusText = 'در حال ذخیره و بررسی نهایی روی گوشی…';
    } else if (isDownloading && phase == RegionDownloadPhase.completed) {
      statusText = '✓ نقشه کامل ساخته و روی گوشی ذخیره شد';
    } else if (isActive) {
      statusText = AppStrings.get(context, ref, 'active_label');
    } else if (installed) {
      statusText = AppStrings.get(context, ref, 'map_downloaded');
    } else {
      statusText = AppStrings.get(context, ref, 'map_not_downloaded');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.glassPanelSoft(context),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FlagBadge(countryCode: region.effectiveCountryCode, glow: isActive),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      fraction != null
                          ? '${(fraction * 100).round()}%'
                          : (installed ? '100%' : '0%'),
                      style: TextStyle(
                        color: isDownloading
                            ? AppColors.primaryAccent(context)
                            : installed
                                ? const Color(0xFF3DDC84)
                                : AppColors.textMuted(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatSize(region.totalSizeMb)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  region.source.attribution,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted(context).withOpacity(0.82),
                    fontSize: 10.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: TextStyle(
                    color: isDownloading
                        ? AppColors.primaryAccent(context)
                        : installed
                            ? const Color(0xFF3DDC84)
                            : AppColors.textMuted(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: installed && !isDownloading
                        ? 1
                        : phase == RegionDownloadPhase.completed
                            ? 1
                            : phase == RegionDownloadPhase.downloading
                                ? (fraction ?? 0).clamp(0.0, 1.0)
                                : fraction ?? 0,
                    minHeight: 6,
                    backgroundColor:
                        AppColors.textMuted(context).withOpacity(0.14),
                    color: progressColor,
                  ),
                ),
                if (isDownloading &&
                    phase == RegionDownloadPhase.completed) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: Color(0xFF3DDC84)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'فایل نقشه + داده‌های لازم در حافظه داخلی اپ ذخیره و آماده استفاده آفلاین است.',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  isDownloading && phase == RegionDownloadPhase.downloading
                      ? '${_formatSize((receivedMb).clamp(0, totalMb))} / ${_formatSize(totalMb > 0 ? totalMb : region.totalSizeMb)}'
                      : isDownloading && phase != RegionDownloadPhase.completed
                          ? 'بررسی نهایی نقشه: ${((fraction ?? 0) * 100).round()}٪'
                          : installed
                              ? '${_formatSize(region.totalSizeMb)} / ${_formatSize(region.totalSizeMb)}'
                              : '0 MB / ${_formatSize(region.totalSizeMb)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted(context),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DeleteButton(
                        enabled: installed || isDownloading,
                        onTap: () async {
                          if (isDownloading) controller.pause();
                          await controller.delete();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        isDownloading: isDownloading,
                        installed: installed,
                        active: isActive,
                        updatable: isUpdatable,
                        onActivate: () async {
                          // «دانلود شده» فقط به معنی وجود فایل .abm نیست. ممکن است
                          // فایل از نسخهٔ قدیمی اپ باقی مانده باشد یا extraction/cache
                          // آن پاک شده باشد. قبل از فعال‌سازی، قرارداد کامل Vector/Search/
                          // Routing را دوباره آماده می‌کنیم تا حالت آفلاین واقعاً قابل استفاده باشد.
                          try {
                            final service = ref.read(abmMapServiceProvider);
                            final vectorService =
                                ref.read(vectorMapServiceProvider);
                            final containerFile =
                                await service.localFile(region.abmFileName);

                            if (!await containerFile.exists() ||
                                await containerFile.length() == 0) {
                              throw const VectorMapInstallException(
                                'فایل نقشه روی دستگاه پیدا نشد؛ ابتدا نقشه را دانلود کنید.',
                              );
                            }

                            if (!await vectorService.isInstalled(
                                containerFile: containerFile)) {
                              await vectorService.prepare(
                                containerFile: containerFile,
                                id: region.id,
                              );
                            }

                            // Do not run a second validation pass here. The
                            // ABM container has already been accepted and the
                            // actual Reader/SQLite consumers will report a
                            // concrete read error only when their subsystem is used.

                            ref.read(abmActiveMapNameProvider.notifier).state =
                                region.abmFileName;
                            ref
                                .read(activeOfflineMapIdProvider.notifier)
                                .state = region.id;
                            await ref.read(settingsRepositoryProvider).setValue(
                                  SettingsRepository.keyActiveMapName,
                                  region.abmFileName,
                                );

                            // Invalidate the async file/readiness providers BEFORE
                            // switching the engine. Otherwise Home can observe the
                            // old Online/null result for one rebuild and keep the
                            // online renderer alive. The engine setter itself performs
                            // a fresh ABM validation and never trusts a cached Future.
                            ref.invalidate(offlineAtlasReadyProvider);
                            ref.invalidate(activeOfflineMapFileProvider);
                            await setRoutingEngineFromWidget(
                                ref, RoutingEngine.abtinmap);
                            ref.invalidate(abmInstalledProvider);
                            ref.invalidate(abmInstalledVersionProvider);
                            ref.invalidate(offlineAtlasReadyProvider);
                            ref.invalidate(activeOfflineMapFileProvider);
                            ref.invalidate(resolvedMapStyleProvider);

                            if (ref.read(routingEngineProvider) !=
                                RoutingEngine.abtinmap) {
                              throw const VectorMapInstallException(
                                'نقشه آماده است اما حالت آفلاین فعال نشد.',
                              );
                            }
                          } catch (error, stack) {
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          }
                        },
                        onTap: () {
                          if (isDownloading) {
                            controller.pause();
                          } else if (isUpdatable) {
                            controller.start();
                          } else if (!installed) {
                            controller.start();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (download.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    download.error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    if (mb >= 1) return '${mb.toStringAsFixed(0)} MB';
    return '${(mb * 1024).toStringAsFixed(0)} KB';
  }
}

class _DeleteButton extends ConsumerWidget {
  const _DeleteButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppColors.danger.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger.withOpacity(0.35)),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline_rounded,
                    size: 17, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(
                  AppStrings.get(context, ref, 'map_delete_action'),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    required this.isDownloading,
    required this.installed,
    required this.active,
    required this.updatable,
    required this.onActivate,
    required this.onTap,
  });

  final bool isDownloading;
  final bool installed;
  final bool active;
  final bool updatable;
  final Future<void> Function() onActivate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);

    IconData icon;
    String label;
    Color color;

    if (isDownloading) {
      icon = Icons.pause_rounded;
      label = AppStrings.get(context, ref, 'map_pause_action');
      color = accent;
    } else if (updatable) {
      icon = Icons.refresh_rounded;
      label = AppStrings.get(context, ref, 'map_update_action');
      color = accent;
    } else if (active) {
      icon = Icons.check_rounded;
      label = AppStrings.get(context, ref, 'active_label');
      color = const Color(0xFF3DDC84);
    } else if (installed) {
      icon = Icons.phone_android_rounded;
      label = AppStrings.get(context, ref, 'map_downloaded');
      color = AppColors.primaryAccent(context);
    } else {
      icon = Icons.download_rounded;
      label = AppStrings.get(context, ref, 'map_download_action');
      color = const Color(0xFF3DDC84);
    }

    final bool tappable = isDownloading || updatable || !installed || !active;

    return Material(
      color: color.withOpacity(0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !tappable
            ? null
            : () {
                if (installed && !active && !updatable) {
                  onActivate();
                } else {
                  onTap();
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.45)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// نشان پرچم کشور. از اموجی پرچم (بر پایه‌ی کد دوحرفی ISO) استفاده می‌شود؛
/// همان روشی که در صفحه‌ی انتخاب زبان هم به‌کار رفته است.
class _FlagBadge extends StatelessWidget {
  const _FlagBadge({required this.countryCode, required this.glow});

  final String countryCode;
  final bool glow;

  static String _flagEmoji(String code) {
    // باگ: کدهای غیرِ دقیقاً ۲حرفی (یا هر id ای که از الگوی کد کشور ISO
    // پیروی نکند — مثل بعضی رکوردهای چندپارتی در مانیفست) همیشه '🌐' خالی
    // برمی‌گرداندند، یعنی پرچمِ کشورهایی مثل آمریکا اصلاً دیده نمی‌شد.
    // اول کدِ ۲حرفیِ واقعی را از ابتدای id استخراج می‌کنیم (پیشوندهای غیرحرفی
    // مثل زیرخط/عدد را نادیده می‌گیریم)، بعد از آن پرچم می‌سازیم.
    final letters = RegExp(r'^[A-Za-z]{2}').stringMatch(code.trim());
    if (letters == null) return '🌐';
    final base = 0x1F1E6;
    final a = letters.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
    final b = letters.toUpperCase().codeUnitAt(1) - 'A'.codeUnitAt(0);
    if (a < 0 || a > 25 || b < 0 || b > 25) return '🌐';
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.glassPanel(context),
        border: Border.all(
          color:
              glow ? accent.withOpacity(0.7) : AppColors.glassBorder(context),
          width: glow ? 1.6 : 1,
        ),
        boxShadow: glow
            ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12)]
            : null,
      ),
      child: ClipOval(
        child: Transform.scale(
          scale: 1.9,
          child: Text(_flagEmoji(countryCode),
              style: const TextStyle(fontSize: 21)),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, required this.retryLabel, required this.onRetry});

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.textMuted(context)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
