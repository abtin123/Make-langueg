import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../abtinmap/abm_models.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../../shared/providers/abm_poi_visibility_providers.dart';
import '../../../shared/providers/app_settings_providers.dart';
import '../../../shared/providers/map_style_providers.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/flag_avatar.dart';
import '../../../shared/widgets/page_header.dart';
import '../../language_settings_hub/language_hub_models.dart';
import '../../language_settings_hub/language_hub_providers.dart';
import '../../offline_maps/presentation/map_download_providers.dart';
import '../../offline_maps/presentation/download_map_screen.dart';
import '../../routing/data/routing_provider.dart';
import '../data/settings_repository.dart';
import '../domain/appearance_settings.dart';
import 'appearance_settings_providers.dart';
import 'map_palette_editor.dart';
import 'settings_repository_provider.dart';

const Map<int, (String, IconData, Color)> _poiInfo = {
  AbmKlass.poiFuel: (
    'poi_fuel',
    Icons.local_gas_station_rounded,
    Color(0xFFFFB454)
  ),
  AbmKlass.poiParking: (
    'poi_parking',
    Icons.local_parking_rounded,
    Color(0xFF69B8FF)
  ),
  AbmKlass.poiSpeedCamera: (
    'poi_speed_camera',
    Icons.speed_rounded,
    Color(0xFFFF6680)
  ),
  AbmKlass.poiSpeedBump: (
    'poi_speed_bump',
    Icons.warning_amber_rounded,
    Color(0xFFFFC247)
  ),
  AbmKlass.poiTrafficLight: (
    'poi_traffic_light',
    Icons.traffic_rounded,
    Color(0xFF62D78D)
  ),
  AbmKlass.poiHospital: (
    'poi_health',
    Icons.local_hospital_rounded,
    Color(0xFFFF7F7F)
  ),
  AbmKlass.poiRestaurant: (
    'poi_public',
    Icons.place_rounded,
    Color(0xFFB68CFF)
  ),
};

/// صفحهٔ مستقلِ تنظیمات نقشه. همهٔ بخش‌های اصلی عمداً باز هستند تا کاربر
/// بدون رفت‌وبرگشت میان تب‌های قبلی، منبع، نما، POI و دانلود نقشه را ببیند.
class MapSettingsScreen extends ConsumerStatefulWidget {
  const MapSettingsScreen({super.key});

  @override
  ConsumerState<MapSettingsScreen> createState() => _MapSettingsScreenState();
}

class _MapSettingsScreenState extends ConsumerState<MapSettingsScreen> {
  bool _downloadsOpen = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    final appearance = ref.watch(appearanceSettingsProvider);
    final mapTilt = ref.watch(mapTiltProvider);
    final poiVisible = ref.watch(abmPoiVisibilityProvider);
    final allPoiVisible = poiVisible == null;
    final routingEngine = ref.watch(routingEngineProvider);
    final mapStyleMode = ref.watch(mapStyleModeProvider);
    final offlineAtlasReady =
        ref.watch(offlineAtlasReadyProvider).valueOrNull ?? false;
    String t(String key) => AppStrings.get(context, ref, key);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(title: t('map_settings')),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.12,
            colors: [accent.withOpacity(0.15), AppColors.background(context)],
          ),
        ),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
              children: [
                _GlassSection(
                  icon: Icons.layers_rounded,
                  iconColor: const Color(0xFF5F9DFF),
                  title: t('map_display'),
                  expanded: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Caption(t('map_source')),
                      _ChoicePill(
                        label: t('offline_map'),
                        icon: Icons.offline_bolt_rounded,
                        selected: routingEngine == RoutingEngine.abtinmap,
                        enabled: offlineAtlasReady,
                        onTap: offlineAtlasReady
                            ? () => _setRoutingEngine(RoutingEngine.abtinmap)
                            : null,
                      ),
                      if (!offlineAtlasReady)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            AppStrings.literal(
                                'ابتدا یک نقشه را از بخش دانلود نقشه دریافت کنید؛ سپس حالت آفلاین فعال می‌شود.'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: AppColors.textMuted(context),
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _ChoicePill(
                        label: AppStrings.literal('نقشه و مسیریابی آنلاین'),
                        icon: Icons.public_rounded,
                        selected: routingEngine == RoutingEngine.online,
                        onTap: () => _setRoutingEngine(RoutingEngine.online),
                      ),
                      if (routingEngine == RoutingEngine.online)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            AppStrings.literal(
                                'نقشه و مسیر از اینترنت دریافت می‌شوند؛ برای استفادهٔ تولیدیِ پرترافیک، endpoint اختصاصی مسیریابی تنظیم شود.'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: AppColors.textMuted(context),
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _Caption(t('map_color_mode')),
                      Row(
                        children: [
                          Expanded(
                            child: _ChoicePill(
                              label: t('day_mode'),
                              icon: Icons.light_mode_rounded,
                              selected: mapStyleMode == MapStyleMode.day,
                              onTap: () => _setMapStyleMode(MapStyleMode.day),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ChoicePill(
                              label: t('night_mode'),
                              icon: Icons.dark_mode_rounded,
                              selected: mapStyleMode == MapStyleMode.night,
                              onTap: () => _setMapStyleMode(MapStyleMode.night),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SettingSwitch(
                        icon: Icons.view_in_ar_rounded,
                        color: const Color(0xFFAF7BFF),
                        title: t('map_three_d'),
                        subtitle: t('map_three_d_desc'),
                        value: appearance.mapPerspective.name == 'threeD',
                        onChanged: (value) => ref
                            .read(appearanceSettingsProvider.notifier)
                            .update((settings) => settings.copyWith(
                                  mapPerspective: value
                                      ? MapPerspective.threeD
                                      : MapPerspective.twoD,
                                )),
                      ),
                      if (appearance.mapPerspective.name == 'threeD') ...[
                        const SizedBox(height: 8),
                        Text('${t('map_angle')}: ${mapTilt.round()}°',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12)),
                        Slider(
                          value: mapTilt.clamp(0.0, 60.0),
                          min: 0,
                          max: 60,
                          divisions: 12,
                          activeColor: accent,
                          onChanged: (value) =>
                              ref.read(mapTiltProvider.notifier).state = value,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const MapPaletteEditor(),
                const SizedBox(height: 12),
                _GlassSection(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFF49C7E7),
                  title: t('poi_map_title'),
                  expanded: true,
                  child: Column(
                    children: [
                      _SettingSwitch(
                        icon: Icons.visibility_rounded,
                        color: const Color(0xFF49C7E7),
                        title: t('show_all_categories'),
                        subtitle: t('poi_selection_desc'),
                        value: allPoiVisible,
                        onChanged: (value) {
                          if (value) {
                            ref
                                .read(abmPoiVisibilityProvider.notifier)
                                .showAll();
                          } else {
                            ref
                                .read(abmPoiVisibilityProvider.notifier)
                                .hideAll();
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      for (final klass in _poiInfo.keys)
                        _PoiToggle(
                          label: t(_poiInfo[klass]!.$1),
                          info: _poiInfo[klass]!,
                          value: allPoiVisible ||
                              (poiVisible?.contains(klass) ?? false),
                          visibleLabel: t('poi_visible'),
                          hiddenLabel: t('poi_hidden'),
                          onChanged: (value) => ref
                              .read(abmPoiVisibilityProvider.notifier)
                              .setKlassEnabled(klass, value),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _GlassSection(
                  icon: Icons.download_for_offline_rounded,
                  iconColor: const Color(0xFF62D78D),
                  title: t('offline_maps_download'),
                  expanded: _downloadsOpen,
                  onToggle: () =>
                      setState(() => _downloadsOpen = !_downloadsOpen),
                  child: _MapDownloadsPanel(),
                ),
                const SizedBox(height: 16),
                Text(
                  t('poi_selection_desc'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                        height: 1.5,
                      ),
                ),
              ],
            ),
            const BottomNav(currentPage: NavKey.settings),
          ],
        ),
      ),
    );
  }

  Future<void> _setMapStyleMode(MapStyleMode mode) async {
    ref.read(mapStyleModeProvider.notifier).state = mode;
    await ref.read(settingsRepositoryProvider).setValue(
          SettingsRepository.keyMapDisplayMode,
          mode.name,
        );
  }

  Future<void> _setRoutingEngine(RoutingEngine engine) async {
    if (engine == RoutingEngine.abtinmap &&
        !await ref.read(offlineAtlasReadyProvider.future)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.literal(
                'برای حالت آفلاین ابتدا نقشه را دانلود کنید.')),
          ),
        );
      }
      return;
    }
    await setRoutingEngineFromWidget(ref, engine);
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.expanded,
    required this.child,
    this.onToggle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final bool expanded;
  final Widget child;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.glassPanelSoft(context),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: AppColors.glassBorder(context), width: 0.7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted(context),
                        ),
                        const Spacer(),
                        Text(title,
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w800,
                                )),
                        const SizedBox(width: 9),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconColor.withOpacity(0.18)),
                          child: Icon(icon, color: iconColor, size: 17),
                        ),
                      ],
                    ),
                  ),
                ),
                if (expanded) ...[const SizedBox(height: 13), child],
              ],
            ),
          ),
        ),
      );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            textAlign: TextAlign.right,
            style: TextStyle(
                color: AppColors.textSecondary(context), fontSize: 12)),
      );
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.icon,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.16)
                : Colors.black.withOpacity(enabled ? 0.10 : 0.05),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.92)
                  : AppColors.glassBorder(context),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected
                    ? accent
                    : (enabled
                        ? AppColors.textSecondary(context)
                        : AppColors.textMuted(context)),
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary(context)
                        : (enabled
                            ? AppColors.textSecondary(context)
                            : AppColors.textMuted(context)),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Switch.adaptive(
                value: value, onChanged: onChanged, activeColor: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Icon(icon, color: color, size: 20),
          ],
        ),
      );
}

class _PoiToggle extends StatelessWidget {
  const _PoiToggle({
    required this.label,
    required this.info,
    required this.value,
    required this.visibleLabel,
    required this.hiddenLabel,
    required this.onChanged,
  });
  final String label;
  final (String, IconData, Color) info;
  final bool value;
  final String visibleLabel;
  final String hiddenLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _SettingSwitch(
        icon: info.$2,
        color: info.$3,
        title: label,
        subtitle: value ? visibleLabel : hiddenLabel,
        value: value,
        onChanged: onChanged,
      );
}

class _MapDownloadsPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(mapDownloadEntriesProvider);
    final catalog = ref.watch(mapCatalogProvider).valueOrNull;
    String t(String key) => AppStrings.get(context, ref, key);
    return entriesAsync.when(
      loading: () => const Center(
          child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => Text(t('map_list_unavailable'),
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.textMuted(context))),
      data: (entries) {
        // دیگر فقط IR نمایش داده نمی‌شود. برای جلوگیری از فشار حافظه،
        // پنل خلاصه چند مورد اول را نشان می‌دهد و فهرست کامل در صفحه دانلود
        // به‌صورت lazy ساخته می‌شود.
        final featured = [...entries]..sort((a, b) {
            final installedOrder =
                (b.installed ? 1 : 0) - (a.installed ? 1 : 0);
            return installedOrder != 0
                ? installedOrder
                : a.title.compareTo(b.title);
          });
        final visibleEntries = featured.take(6).toList(growable: false);
        if (visibleEntries.isEmpty) {
          return Text(t('map_list_unavailable'),
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.textMuted(context)));
        }
        final primary = visibleEntries.first;
        final rest = visibleEntries.skip(1).toList();

        void handle(DownloadEntry entry) {
          final region = catalog?.byId(entry.id);
          if (region == null) return;
          if (entry.installed) {
            unawaited(activateMapRegion(ref, region));
          } else {
            downloadMapRegion(ref, region);
          }
        }

        Future<void> remove(DownloadEntry entry) async {
          final region = catalog?.byId(entry.id);
          if (region == null || !entry.installed) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(AppStrings.literal('حذف نقشه')),
              content:
                  Text(AppStrings.getWithParams(context, ref, 'settings_46a0a9a539c5', {'name': entry.title})),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(AppStrings.literal('انصراف')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(AppStrings.literal('حذف')),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await ref
                .read(regionDownloadControllerProvider(region).notifier)
                .delete();
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MapDownloadCard(children: [
              _MapDownloadRow(
                entry: primary,
                downloadLabel: t('download_label'),
                selectLabel: t('select_label'),
                activeLabel: t('active_label'),
                subtitleOverride:
                    primary.installed ? t('close_zoom_map_ready') : null,
                onTap: () => handle(primary),
                onDelete: primary.installed ? () => remove(primary) : null,
              ),
            ]),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MapDownloadCard(
                children: [
                  for (var i = 0; i < rest.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                    _MapDownloadRow(
                      entry: rest[i],
                      downloadLabel: t('download_label'),
                      selectLabel: t('select_label'),
                      activeLabel: t('active_label'),
                      onTap: () => handle(rest[i]),
                      onDelete:
                          rest[i].installed ? () => remove(rest[i]) : null,
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadMapScreen()),
              ),
              icon: const Icon(Icons.public_rounded, size: 18),
              label: Text(AppStrings.literal('مشاهده همه کشورها')),
            ),
            Text(
              t('download_select_other_region'),
              textAlign: TextAlign.right,
              style:
                  TextStyle(color: AppColors.textMuted(context), fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

class _MapDownloadCard extends StatelessWidget {
  const _MapDownloadCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder(context)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

class _MapDownloadRow extends StatelessWidget {
  const _MapDownloadRow({
    required this.entry,
    required this.downloadLabel,
    required this.selectLabel,
    required this.activeLabel,
    required this.onTap,
    this.onDelete,
    this.subtitleOverride,
  });
  final DownloadEntry entry;
  final String downloadLabel;
  final String selectLabel;
  final String activeLabel;
  final String? subtitleOverride;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final downloading = entry.progress != null;
    final subtitle = subtitleOverride ?? (entry.subtitle ?? '');
    final buttonLabel = downloading
        ? '${((entry.progress ?? 0) * 100).round()}%'
        : entry.installed
            ? (entry.selected ? activeLabel : selectLabel)
            : downloadLabel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: downloading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _MapFlagBadge(
                flag: entry.flag ?? 'assets/images/flags/un.svg',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(entry.title,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5)),
                        ),
                        if (entry.selected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF62D78D), size: 17),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: AppColors.textMuted(context),
                              fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _MapPillButton(
                  label: buttonLabel,
                  active: entry.selected,
                  onTap: downloading ? null : onTap),
              if (onDelete != null)
                IconButton(
                  tooltip: AppStrings.literal('حذف نقشه'),
                  onPressed: () => onDelete!(),
                  icon: Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 21),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapFlagBadge extends StatelessWidget {
  const _MapFlagBadge({required this.flag, this.icon});
  final String flag;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => icon != null
      ? Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: Colors.white.withOpacity(0.06),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black45, blurRadius: 4, offset: Offset(0, 1))
            ],
          ),
          child: Icon(icon, color: const Color(0xFF62D78D), size: 20),
        )
      : FlagAvatar.rectangle(flag: flag, size: 38);
}

class _MapPillButton extends StatelessWidget {
  const _MapPillButton(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Material(
      color: active ? accent.withOpacity(0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.75), width: 1.3),
          ),
          child: Text(label,
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}
