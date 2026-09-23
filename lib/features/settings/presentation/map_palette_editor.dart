import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/map_style_providers.dart';
import 'appearance/shared_widgets.dart' show AppColorSwatch, ColorPickerSheet;

/// کنترل مستقیم رنگ‌های واقعی نقشه. هر تغییر فوراً در palette ذخیره می‌شود.
class MapPaletteEditor extends ConsumerWidget {
  const MapPaletteEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String key) => AppStrings.get(context, ref, key);
    final mode = ref.watch(mapStyleModeProvider);
    final palette = mode == MapStyleMode.day
        ? ref.watch(offlineLightPaletteProvider)
        : ref.watch(offlineDarkPaletteProvider);
    final notifier = mode == MapStyleMode.day
        ? ref.read(offlineLightPaletteProvider.notifier)
        : ref.read(offlineDarkPaletteProvider.notifier);
    final presets = mode == MapStyleMode.day
        ? const <(MapPalettePreset, String, IconData)>[
            (
              MapPalettePreset.kartaDay,
              'map_preset_karta_day',
              Icons.wb_sunny_rounded
            ),
            (
              MapPalettePreset.sandstoneDay,
              'map_preset_sandstone_day',
              Icons.landscape_rounded
            ),
          ]
        : const <(MapPalettePreset, String, IconData)>[
            (
              MapPalettePreset.kartaNight,
              'map_preset_karta_night',
              Icons.dark_mode_rounded
            ),
            (
              MapPalettePreset.midnightNight,
              'map_preset_midnight_night',
              Icons.nightlight_round
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassPanelSoft(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('map_palette_title'),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            t('map_palette_desc'),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                _PresetButton(
                  label: t(preset.$2),
                  icon: preset.$3,
                  onTap: () => notifier.applyPreset(preset.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _PaletteGroup(
            title: t('map_palette_land_group'),
            items: <(OfflinePaletteField, String)>[
              (OfflinePaletteField.background, t('map_color_ground')),
              (OfflinePaletteField.urban, t('map_color_urban')),
              (OfflinePaletteField.green, t('map_color_green')),
              (OfflinePaletteField.water, t('map_color_water')),
              (OfflinePaletteField.label, t('map_color_labels')),
            ],
            palette: palette,
            onColor: notifier.setColor,
          ),
          const SizedBox(height: 14),
          _PaletteGroup(
            title: t('map_palette_roads_group'),
            items: <(OfflinePaletteField, String)>[
              (OfflinePaletteField.roadMotorway, t('map_color_motorway')),
              (OfflinePaletteField.roadTrunk, t('map_color_trunk')),
              (OfflinePaletteField.roadPrimary, t('map_color_primary')),
              (OfflinePaletteField.roadSecondary, t('map_color_secondary')),
              (OfflinePaletteField.roadLocal, t('map_color_local')),
            ],
            palette: palette,
            onColor: notifier.setColor,
          ),
          const SizedBox(height: 14),
          _RoadWidthControl(
            label: t('map_road_width'),
            valueLabel: t('map_road_width_value').replaceAll(
              '{value}',
              '${(palette.roadWidthScale * 100).round()}',
            ),
            value: palette.roadWidthScale,
            onChanged: notifier.setRoadWidthScale,
          ),
        ],
      ),
    );
  }
}

class _RoadWidthControl extends StatelessWidget {
  const _RoadWidthControl({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        Slider(
          min: 0.6,
          max: 1.8,
          divisions: 12,
          value: value.clamp(0.6, 1.8).toDouble(),
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _PaletteGroup extends StatelessWidget {
  const _PaletteGroup({
    required this.title,
    required this.items,
    required this.palette,
    required this.onColor,
  });

  final String title;
  final List<(OfflinePaletteField, String)> items;
  final OfflineMapPalette palette;
  final Future<void> Function(OfflinePaletteField field, Color color) onColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              for (final item in items)
                _ColorControl(
                  label: item.$2,
                  color: palette.colorOf(item.$1),
                  onColor: (color) => onColor(item.$1, color),
                ),
            ],
          ),
        ],
      );
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Future<void> Function(Color color) onColor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 104,
        child: Column(
          children: [
            AppColorSwatch(
              color: color,
              selected: false,
              onTap: () async {
                final selected = await ColorPickerSheet.show(context, color);
                if (selected == null || !context.mounted) return;
                await onColor(selected);
              },
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
            ),
          ],
        ),
      );
}
