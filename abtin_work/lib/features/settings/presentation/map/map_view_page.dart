import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abtin_maps/abtinmap/abm_models.dart';
import 'package:abtin_maps/core/theme/app_colors.dart';
import 'package:abtin_maps/shared/providers/abtinmap_providers.dart';
import 'package:abtin_maps/shared/providers/abm_poi_visibility_providers.dart';
import 'package:abtin_maps/shared/providers/app_settings_providers.dart';
import 'package:abtin_maps/shared/providers/map_style_providers.dart';
import 'package:abtin_maps/features/routing/data/routing_provider.dart';
import 'package:abtin_maps/features/settings/data/settings_repository.dart';
import 'package:abtin_maps/features/settings/presentation/appearance_settings_providers.dart';
import 'package:abtin_maps/features/settings/presentation/settings_repository_provider.dart';
import 'package:abtin_maps/features/offline_maps/presentation/offline_maps_providers.dart';

/// صفحهٔ تنظیمات نقشه. Atlas فعلی رنگ خیابان‌ها را از tileهای پختهٔ سرور
/// می‌خواند؛ رنگ مسیر مسیریابی در صفحهٔ مستقل تنظیمات مسیر کنترل می‌شود.
class MapViewPage extends StatelessWidget {
  const MapViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: MapSettingsContent(),
    );
  }
}

class MapSettingsContent extends StatefulWidget {
  const MapSettingsContent({super.key});

  @override
  State<MapSettingsContent> createState() => _MapSettingsContentState();
}

class _MapSettingsContentState extends State<MapSettingsContent> {
  int _activeTab = 0;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.background(context).withOpacity(0.58),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder(context)),
          ),
          child: Row(
            children: [
              _MapTab(
                label: AppStrings.literal('نقاط نمایشی روی نقشه'),
                selected: _activeTab == 0,
                accent: accent,
                onTap: () => setState(() => _activeTab = 0),
              ),
              const SizedBox(width: 4),
              _MapTab(
                label: AppStrings.literal('تنظیمات نمایش نقشه'),
                selected: _activeTab == 1,
                accent: accent,
                onTap: () => setState(() => _activeTab = 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_activeTab == 0)
          const _PoiSettings()
        else
          const _MapDisplaySettings(),
      ],
    );
  }
}

class _MapTab extends StatelessWidget {
  const _MapTab({
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
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    selected ? Colors.white : AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PoiSettings extends ConsumerWidget {
  const _PoiSettings();

  static const _labels = <int, (String, IconData)>{
    AbmKlass.poiFuel: ('پمپ بنزین و شارژ', Icons.local_gas_station_rounded),
    AbmKlass.poiParking: ('پارکینگ', Icons.local_parking_rounded),
    AbmKlass.poiHospital: ('بیمارستان', Icons.local_hospital_rounded),
    AbmKlass.poiPharmacy: ('داروخانه', Icons.medication_rounded),
    AbmKlass.poiRestaurant: ('رستوران', Icons.restaurant_rounded),
    AbmKlass.poiCafe: ('کافه', Icons.local_cafe_rounded),
    AbmKlass.poiBank: ('بانک', Icons.account_balance_rounded),
    AbmKlass.poiHotel: ('هتل', Icons.hotel_rounded),
    AbmKlass.poiPark: ('پارک', Icons.park_rounded),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(abmPoiVisibilityProvider);
    final allShown = visible == null;
    final notifier = ref.read(abmPoiVisibilityProvider.notifier);
    return _SectionCard(
      title: AppStrings.literal('نقاط نمایشی روی نقشه'),
      icon: Icons.place_outlined,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(AppStrings.literal('نمایش همه دسته‌ها'),
                textAlign: TextAlign.right),
            value: allShown,
            onChanged: (enabled) {
              if (enabled) notifier.showAll();
            },
            activeThumbColor: AppColors.primaryAccent(context),
          ),
          const Divider(height: 1),
          for (final klass in AbmKlass.selectablePoiKlasses)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(_labels[klass]?.$2 ?? Icons.place_rounded),
              title: Text(
                  AppStrings.literal(_labels[klass]?.$1 ?? 'نقطه روی نقشه'),
                  textAlign: TextAlign.right),
              value: allShown || (visible?.contains(klass) ?? false),
              onChanged: (enabled) => notifier.setKlassEnabled(klass, enabled),
              activeThumbColor: AppColors.primaryAccent(context),
            ),
        ],
      ),
    );
  }
}

class _MapDisplaySettings extends ConsumerWidget {
  const _MapDisplaySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perspective = ref.watch(mapPerspectiveProvider);
    final tilt = ref.watch(appearanceSettingsProvider).mapTilt;
    final styleMode = ref.watch(mapStyleModeProvider);
    final routingEngine = ref.watch(routingEngineProvider);
    final offlineAtlasReady =
        ref.watch(offlineAtlasReadyProvider).valueOrNull ?? false;
    final installedOfflineIds =
        ref.watch(abmInstalledMapIdsProvider).valueOrNull ?? const <String>{};
    // تا وقتی validation async تمام شود، وجود حداقل یک ABM نصب‌شده باید
    // گزینهٔ آفلاین را قابل انتخاب نگه دارد؛ خودِ setRoutingEngineFromWidget
    // بعداً اعتبار فایل را قطعی می‌کند.
    final offlineSelectable =
        offlineAtlasReady || installedOfflineIds.isNotEmpty;
    final repo = ref.read(settingsRepositoryProvider);
    final accent = AppColors.primaryAccent(context);

    return _SectionCard(
      title: AppStrings.literal('تنظیمات نمایش نقشه'),
      icon: Icons.layers_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Caption('منبع نقشه'),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('آفلاین'),
                  selected: routingEngine == RoutingEngine.abtinmap,
                  enabled: offlineSelectable,
                  onTap: () =>
                      setRoutingEngineFromWidget(ref, RoutingEngine.abtinmap),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('آنلاین'),
                  selected: routingEngine == RoutingEngine.online,
                  onTap: () =>
                      setRoutingEngineFromWidget(ref, RoutingEngine.online),
                ),
              ),
            ],
          ),
          if (!offlineSelectable)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                AppStrings.literal(
                    'حالت آفلاین بعد از دانلود نقشه فعال می‌شود.'),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          const SizedBox(height: 16),
          const _Caption('نمای نقشه'),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('دوبعدی'),
                  selected: perspective == MapPerspective.twoD,
                  onTap: () =>
                      ref.read(appearanceSettingsProvider.notifier).update(
                            (settings) => settings.copyWith(
                                mapPerspective: MapPerspective.twoD),
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('سه‌بعدی'),
                  selected: perspective == MapPerspective.threeD,
                  onTap: () =>
                      ref.read(appearanceSettingsProvider.notifier).update(
                            (settings) => settings.copyWith(
                                mapPerspective: MapPerspective.threeD),
                          ),
                ),
              ),
            ],
          ),
          if (perspective == MapPerspective.threeD) ...[
            const SizedBox(height: 12),
            Text(AppStrings.getWithParams(context, ref, 'settings_410ba8e2777c', {'angle': tilt.round()}),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: AppColors.textSecondary(context), fontSize: 12)),
            Slider(
              value: tilt.clamp(0.0, 60.0).toDouble(),
              min: 0,
              max: 60,
              divisions: 12,
              activeColor: accent,
              onChanged: (value) => ref
                  .read(appearanceSettingsProvider.notifier)
                  .update((settings) => settings.copyWith(mapTilt: value)),
            ),
          ],
          const SizedBox(height: 10),
          const _Caption('حالت رنگ نقشه'),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('روشن'),
                  selected: styleMode == MapStyleMode.day,
                  onTap: () {
                    ref.read(mapStyleModeProvider.notifier).state =
                        MapStyleMode.day;
                    repo.setValue(SettingsRepository.keyMapDisplayMode,
                        MapStyleMode.day.name);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceButton(
                  label: AppStrings.literal('تیره'),
                  selected: styleMode == MapStyleMode.night,
                  onTap: () {
                    ref.read(mapStyleModeProvider.notifier).state =
                        MapStyleMode.night;
                    repo.setValue(SettingsRepository.keyMapDisplayMode,
                        MapStyleMode.night.name);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _RoadPaletteEditor(),
        ],
      ),
    );
  }
}

/// رنگ چهار سطح راه در Atlas فعلی هنگام ساخت سرور داخل raster tile پخته
/// می‌شود. بنابراین این بخش برای جلوگیری از تنظیمِ ظاهراً قابل‌ویرایش اما
/// بی‌اثر، فقط پالت فعلی Atlas را نشان می‌دهد.
class _RoadPaletteEditor extends ConsumerWidget {
  const _RoadPaletteEditor();

  static const _items = <(OfflinePaletteField, String)>[
    (OfflinePaletteField.roadMotorway, 'بزرگراه و آزادراه'),
    (OfflinePaletteField.roadPrimary, 'خیابان اصلی'),
    (OfflinePaletteField.roadSecondary, 'خیابان فرعی'),
    (OfflinePaletteField.roadLocal, 'کوچه و معبر محلی'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(mapStyleModeProvider);
    final palette = mode == MapStyleMode.day
        ? ref.watch(offlineLightPaletteProvider)
        : ref.watch(offlineDarkPaletteProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Caption('رنگ خیابان‌های Atlas'),
        Text(
          AppStrings.literal(
              'رنگ خیابان‌ها و POIها در tileهای Atlas سرور پخته شده است. برای تغییر واقعی باید Atlas با پالت جدید ساخته شود؛ رنگ مسیر همچنان جداگانه در تنظیمات مسیر تغییر می‌کند.'),
          textAlign: TextAlign.right,
          style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              height: 1.55),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _items)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 72) / 2,
                child: Container(
                  alignment: Alignment.centerRight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: palette.colorOf(item.$1).withValues(alpha: 0.58),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: palette.colorOf(item.$1),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.literal(item.$2),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Icon(icon, color: AppColors.primaryAccent(context)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(AppStrings.literal(text),
            textAlign: TextAlign.right,
            style: TextStyle(
                color: AppColors.textSecondary(context), fontSize: 12)),
      );
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? accent.withOpacity(0.16) : Colors.transparent,
        side: BorderSide(
            color: selected ? accent : AppColors.glassBorder(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? accent
              : (enabled ? AppColors.textSecondary(context) : Colors.white38),
        ),
      ),
    );
  }
}
