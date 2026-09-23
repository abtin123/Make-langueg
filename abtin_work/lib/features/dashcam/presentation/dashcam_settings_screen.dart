import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/page_header.dart';
import '../../settings/presentation/appearance/shared_widgets.dart';
import 'dashcam_settings_providers.dart';

/// صفحهٔ «دوربین هوشمند خودرو» (AI DashCam): ضبط ویدیو و دستیارِ هوشمندِ
/// رانندگی — با هدرِ مشترکِ [PageHeader]، رنگِ داینامیکِ
/// [AppColors.primaryAccent] و نوارِ پایینِ مشترکِ [BottomNav].
class DashCamSettingsScreen extends ConsumerWidget {
  const DashCamSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);
    final settings = ref.watch(dashCamSettingsProvider);
    final notifier = ref.read(dashCamSettingsProvider.notifier);
    String t(String key) => AppStrings.get(context, ref, key);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
        title: t('ai_dashcam_title'),
        subtitle: t('ai_dashcam_desc'),
      ),
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
                _DashCamGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SwitchRow(
                        icon: Icons.videocam_rounded,
                        iconColor: const Color(0xFFFF6680),
                        title: t('dashcam_recording'),
                        value: settings.recordingEnabled,
                        onChanged: (v) => notifier
                            .update((s) => s.copyWith(recordingEnabled: v)),
                      ),
                      const RowDivider(),
                      Opacity(
                        opacity: settings.recordingEnabled ? 1 : 0.4,
                        child: _VideoSizeSlider(
                          value: settings.videoSizeMinutes,
                          enabled: settings.recordingEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(videoSizeMinutes: v)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DashCamGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SwitchRow(
                        icon: Icons.shield_rounded,
                        iconColor: const Color(0xFF62D78D),
                        title: t('dashcam_driver_assistance'),
                        value: settings.driverAssistanceEnabled,
                        onChanged: (v) => notifier.update(
                            (s) => s.copyWith(driverAssistanceEnabled: v)),
                      ),
                      Opacity(
                        opacity: settings.driverAssistanceEnabled ? 1 : 0.4,
                        child: IgnorePointer(
                          ignoring: !settings.driverAssistanceEnabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const RowDivider(),
                              _SwitchRow(
                                icon: Icons.height_rounded,
                                iconColor: const Color(0xFF5F9DFF),
                                title: t('dashcam_fixed_camera_height'),
                                value: settings.fixedCameraHeight,
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(fixedCameraHeight: v)),
                              ),
                              const SizedBox(height: 14),
                              _MeterSlider(
                                title: t('dashcam_camera_height'),
                                value: settings.cameraHeightMeters,
                                min: 1.0,
                                max: 3.0,
                                unit: t('dashcam_meters_short'),
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(cameraHeightMeters: v)),
                              ),
                              const SizedBox(height: 14),
                              _MeterSlider(
                                title: t('dashcam_vehicle_width'),
                                value: settings.vehicleWidthMeters,
                                min: 1.0,
                                max: 3.0,
                                unit: t('dashcam_meters_short'),
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(vehicleWidthMeters: v)),
                              ),
                              const SizedBox(height: 14),
                              _MeterSlider(
                                title: t('dashcam_camera_lateral_displacement'),
                                value: settings.cameraLateralDisplacementMeters,
                                min: -1.0,
                                max: 1.0,
                                unit: t('dashcam_meters_short'),
                                onChanged: (v) => notifier.update((s) =>
                                    s.copyWith(
                                        cameraLateralDisplacementMeters: v)),
                              ),
                              const SizedBox(height: 4),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_forward_collision'),
                                value: settings.forwardCollision,
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(forwardCollision: v)),
                              ),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_dangerous_headway'),
                                value: settings.dangerousHeadway,
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(dangerousHeadway: v)),
                              ),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_stop_and_go'),
                                value: settings.stopAndGo,
                                onChanged: (v) => notifier
                                    .update((s) => s.copyWith(stopAndGo: v)),
                              ),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_lane_departure_solid'),
                                value: settings.laneDepartureSolid,
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(laneDepartureSolid: v)),
                              ),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_lane_departure_dashed'),
                                value: settings.laneDepartureDashed,
                                onChanged: (v) => notifier.update(
                                    (s) => s.copyWith(laneDepartureDashed: v)),
                              ),
                              const RowDivider(),
                              _AlertLevelRow(
                                title: t('dashcam_traffic_sign_recognition'),
                                value: settings.trafficSignRecognition,
                                onChanged: (v) => notifier.update((s) =>
                                    s.copyWith(trafficSignRecognition: v)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
}

// ============================================================
// اجزای این صفحه.
// ============================================================

class _DashCamGlassCard extends StatelessWidget {
  const _DashCamGlassCard({required this.child});
  final Widget child;

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
            child: child,
          ),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Switch.adaptive(
            value: value,
            activeColor: AppColors.primaryAccent(context),
            onChanged: onChanged,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: iconColor.withOpacity(0.16)),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ],
      );
}

/// اسلایدرِ حجمِ ویدیو: ۱۰ تا ۶۰ دقیقه به‌همراهِ گزینهٔ نامحدود (∞) در
/// انتهای بازه؛ حجم تقریبیِ فایل هم برای راهنمایی نمایش داده می‌شود.
class _VideoSizeSlider extends StatelessWidget {
  const _VideoSizeSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  static const int _minMinutes = 10;
  static const int _maxMinutes = 60;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    final unlimited = value <= 0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _VideoSizeCaption(minutes: value),
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withOpacity(0.18),
              thumbColor: accent,
              overlayColor: accent.withOpacity(0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: (unlimited ? _maxMinutes + 10 : value)
                  .clamp(_minMinutes, _maxMinutes + 10)
                  .toDouble(),
              min: _minMinutes.toDouble(),
              max: (_maxMinutes + 10).toDouble(),
              onChanged: enabled
                  ? (v) => onChanged(v.round() > _maxMinutes ? 0 : v.round())
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_minMinutes',
                    style: TextStyle(
                        color: AppColors.textMuted(context), fontSize: 11.5)),
                Text('∞',
                    style: TextStyle(
                        color: AppColors.textMuted(context), fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSizeCaption extends ConsumerWidget {
  const _VideoSizeCaption({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlimited = minutes <= 0;
    final sizeGb = (minutes * 0.0353);
    final text = unlimited
        ? AppStrings.get(context, ref, 'dashcam_video_size_unlimited')
        : AppStrings.getWithParams(context, ref, 'dashcam_video_size_value', {
            'value': minutes,
            'size': sizeGb.toStringAsFixed(2),
          });
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    );
  }
}

/// اسلایدرِ عمومیِ اندازه‌گیریِ متریک (ارتفاع، عرض، جابه‌جاییِ جانبی).
class _MeterSlider extends StatelessWidget {
  const _MeterSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: AppColors.textSecondary(context), fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${value.toStringAsFixed(2)} $unit',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withOpacity(0.18),
              thumbColor: accent,
              overlayColor: accent.withOpacity(0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.toStringAsFixed(2)} $unit',
                  style: TextStyle(
                      color: AppColors.textMuted(context), fontSize: 11)),
              Text('${max.toStringAsFixed(2)} $unit',
                  style: TextStyle(
                      color: AppColors.textMuted(context), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

/// سطرِ انتخابِ سطحِ حساسیتِ یک هشدارِ دستیارِ رانندگی: خاموش/کم/معمولی/زیاد.
class _AlertLevelRow extends ConsumerWidget {
  const _AlertLevelRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final DashCamAlertLevel value;
  final ValueChanged<DashCamAlertLevel> onChanged;

  String _labelFor(
      BuildContext context, WidgetRef ref, DashCamAlertLevel level) {
    switch (level) {
      case DashCamAlertLevel.off:
        return AppStrings.get(context, ref, 'dashcam_level_off');
      case DashCamAlertLevel.low:
        return AppStrings.get(context, ref, 'dashcam_level_low');
      case DashCamAlertLevel.normal:
        return AppStrings.get(context, ref, 'dashcam_level_normal');
      case DashCamAlertLevel.high:
        return AppStrings.get(context, ref, 'dashcam_level_high');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                for (final level in DashCamAlertLevel.values) ...[
                  Expanded(
                    child: _LevelChip(
                      label: _labelFor(context, ref, level),
                      selected: value == level,
                      accent: accent,
                      onTap: () => onChanged(level),
                    ),
                  ),
                  if (level != DashCamAlertLevel.values.last)
                    const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
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
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(colors: [
                      AppColors.primaryAccentLight(context),
                      accent,
                    ])
                  : null,
              color: selected ? null : AppColors.surfaceMuted(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color:
                    selected ? Colors.white : AppColors.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      );
}
