import 'dart:math' as math;

import 'dart:ui';
import '../../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/page_header.dart';
import '../../vehicle/presentation/car_marker.dart';
import '../../vehicle/presentation/nav_arrow_painter.dart';
import '../../vehicle/presentation/vehicle_provider.dart';
import 'appearance_settings_providers.dart';

/// تنظیمات مکان‌نما با دو تب مستقل: «فلش» و «خودرو». با زدن هر دکمه، هم
/// پیش‌نمایشِ زنده و هم بخشِ تنظیماتِ زیرش عوض می‌شود. تبِ فعال از
/// [activeAppearanceTabProvider] می‌آید — همان مقداری که HomeScreen برای
/// انتخاب نوعِ marker روی نقشهٔ واقعی می‌خواند، پس این صفحه دقیقاً همان
/// چیزی را کنترل می‌کند که روی نقشه دیده می‌شود.
class MarkerSettingsScreen extends ConsumerStatefulWidget {
  const MarkerSettingsScreen({super.key});

  @override
  ConsumerState<MarkerSettingsScreen> createState() =>
      _MarkerSettingsScreenState();
}

class _MarkerSettingsScreenState extends ConsumerState<MarkerSettingsScreen> {
  static const _pinColors = <Color>[
    Color(0xFF9654E8),
    Color(0xFFFFFFFF),
    Color(0xFF080A0E),
    Color(0xFF1464E8),
    Color(0xFF39C2E7),
    Color(0xFF65B52E),
    Color(0xFFF0B719),
    Color(0xFFD92531),
  ];

  Future<void> _update(
    AppearanceSettings Function(AppearanceSettings) transform,
  ) {
    return ref.read(appearanceSettingsProvider.notifier).update(transform);
  }

  Future<void> _chooseCustomPinColor() async {
    final current = ref.read(appearanceSettingsProvider);
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => _CustomColorDialog(selected: current.pinColor),
    );
    if (!mounted || picked == null) return;
    await _update((s) => s.copyWith(pinColor: picked));
  }

  Future<void> _reset() async {
    await ref.read(appearanceSettingsProvider.notifier).reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              AppStrings.literal('تنظیمات مکان‌نما به حالت پیش‌فرض برگشت.'))),
    );
  }

  Future<void> _cycleModel(int direction) async {
    final count = vehicleModels.length;
    final current = ref.read(appearanceSettingsProvider).vehicleModelIndex;
    final next = (current + direction) % count;
    await _update((s) => s.copyWith(
          vehicleModelIndex: next < 0 ? next + count : next,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceSettingsProvider);
    final accent = AppColors.primaryAccent(context);
    final activeTab = ref.watch(activeAppearanceTabProvider);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(title: AppStrings.literal('تنظیمات مکان‌نما')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.15,
              colors: [accent.withOpacity(.16), AppColors.background(context)],
            ),
          ),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                children: [
                  _LivePreviewSection(settings: settings),
                  const SizedBox(height: 12),
                  _MarkerTypeSwitcher(
                    activeTab: activeTab,
                    accent: accent,
                    onSelect: (tab) => ref
                        .read(activeAppearanceTabProvider.notifier)
                        .state = tab,
                  ),
                  const SizedBox(height: 12),
                  if (activeTab == AppearanceTab.pin)
                    _GlassSection(
                      icon: Icons.near_me_rounded,
                      iconColor: accent,
                      title: AppStrings.literal('تنظیمات فلش'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingCaption('انتخاب رنگ فلش'),
                          _ColorSwatches(
                            colors: _pinColors,
                            selected: settings.pinColor,
                            onSelected: (color) =>
                                _update((s) => s.copyWith(pinColor: color)),
                            onCustom: _chooseCustomPinColor,
                          ),
                          const SizedBox(height: 16),
                          _PercentSlider(
                            title: AppStrings.literal('اندازهٔ فلش'),
                            value: settings.pinSize,
                            min: 50,
                            max: 150,
                            divisions: 20,
                            suffix: '%',
                            onChanged: (value) => ref
                                .read(pinSizeProvider.notifier)
                                .state = value,
                          ),
                          const SizedBox(height: 8),
                          _SettingSwitch(
                            title: AppStrings.literal('سایه و درخشش فلش'),
                            subtitle: AppStrings.literal(
                                'نمایش هالهٔ رنگی زیر مکان‌نما روی نقشه'),
                            icon: Icons.auto_awesome_rounded,
                            color: accent,
                            value: settings.pinShadowEnabled,
                            onChanged: (value) => ref
                                .read(pinShadowEnabledProvider.notifier)
                                .state = value,
                          ),
                        ],
                      ),
                    )
                  else
                    _GlassSection(
                      icon: Icons.directions_car_filled_rounded,
                      iconColor: accent,
                      title: AppStrings.literal('تنظیمات خودرو'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingCaption('مدل خودرو'),
                          Row(
                            children: [
                              _CircleAction(
                                // در رابط RTL، فلش راست باید به مدل بعدی برود.
                                icon: Icons.chevron_left_rounded,
                                onTap: () => _cycleModel(1),
                              ),
                              Expanded(
                                child: Text(
                                  AppStrings.get(
                                    context,
                                    ref,
                                    vehicleModelNameKeys[
                                        settings.vehicleModelIndex.clamp(0,
                                            vehicleModelNameKeys.length - 1)],
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _CircleAction(
                                // در رابط RTL، فلش چپ باید به مدل قبلی برگردد.
                                icon: Icons.chevron_right_rounded,
                                onTap: () => _cycleModel(-1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _PercentSlider(
                            title: AppStrings.literal('اندازهٔ خودرو'),
                            value: settings.carSizePercent,
                            min: 70,
                            max: 150,
                            divisions: 16,
                            suffix: '%',
                            onChanged: (value) => ref
                                .read(carSizePercentProvider.notifier)
                                .state = value,
                          ),
                          const SizedBox(height: 16),
                          _AngleSlider(
                            value: settings.vehicleViewAngleDegrees,
                            onChanged: (value) => ref
                                .read(vehicleViewAngleProvider.notifier)
                                .state = value,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label:
                        Text(AppStrings.literal('بازنشانی تنظیمات مکان‌نما')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.glassBorder(context)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              const BottomNav(currentPage: NavKey.settings),
            ],
          ),
        ),
      ),
    );
  }
}

/// دو دکمهٔ «فلش» و «خودرو» — با زدن هر کدام، هم پیش‌نمایش و هم بخشِ
/// تنظیماتِ زیرِ آن به تبِ همان نوع مکان‌نما می‌رود.
class _MarkerTypeSwitcher extends StatelessWidget {
  const _MarkerTypeSwitcher({
    required this.activeTab,
    required this.accent,
    required this.onSelect,
  });

  final AppearanceTab activeTab;
  final Color accent;
  final ValueChanged<AppearanceTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background(context).withOpacity(0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        children: [
          _MarkerTypeTab(
            label: AppStrings.literal('فلش'),
            icon: Icons.near_me_rounded,
            selected: activeTab == AppearanceTab.pin,
            accent: accent,
            onTap: () => onSelect(AppearanceTab.pin),
          ),
          const SizedBox(width: 4),
          _MarkerTypeTab(
            label: AppStrings.literal('خودرو'),
            icon: Icons.directions_car_filled_rounded,
            selected: activeTab == AppearanceTab.car,
            accent: accent,
            onTap: () => onSelect(AppearanceTab.car),
          ),
        ],
      ),
    );
  }
}

class _MarkerTypeTab extends StatelessWidget {
  const _MarkerTypeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected
                      ? Colors.white
                      : AppColors.textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

/// پیش‌نمایش زنده — کادر شیشه‌ای که خودرو یا پیکان انتخاب‌شده را در همان
/// اندازه/زاویه‌ای که روی نقشه واقعی نمایش داده می‌شود، نشان می‌دهد.
///
/// نکات رفتاری (طبق درخواست کاربر):
/// 1. نمای پیش‌فرض همیشه «از بالا» است (cameraAngleDegrees=0) و کاربر با
///    اسلایدر «نمایش خودرو» از بالا تا نمای پشت (۹۰ درجه) پایین می‌آورد.
/// 2. چرخش فقط از طریق اسلایدرها انجام می‌شود؛ لمس داخل پیش‌نمایش هیچ
///    چرخشی روی مدل ایجاد نمی‌کند (interactive:false).
/// 3. باکس پیش‌نمایش به‌قدر کافی بزرگ است که حتی در بیشترین carSizePercent
///    خودرو از آن بیرون نزند.
/// 4. خودرو با headingDeg=0 روی خط جاده فرضی پایین کادر قرار می‌گیرد،
///    یعنی جلوی خودرو دقیقاً در راستای جاده است (نه عمود بر آن).
class _LivePreviewSection extends ConsumerWidget {
  const _LivePreviewSection({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);
    final isCar = settings.activeTab == AppearanceTab.car;
    final previewBoxHeight = isCar ? 220.0 : 190.0;
    // پیش‌نمایش باید همان مقیاس طبیعی نقشه را نشان دهد؛ رشدِ sqrt مانع
    // از جهش شدید اندازه در انتهای اسلایدر می‌شود.
    final previewCarSize = isCar
        ? (110.0 *
                math.sqrt(settings.carSizePercent.clamp(70.0, 150.0) / 100.0))
            .clamp(88.0, 135.0)
            .toDouble()
        : 120.0;
    return _GlassSection(
      icon: Icons.near_me_rounded,
      iconColor: accent,
      title: AppStrings.literal('پیش‌نمایش زنده'),
      child: Column(
        children: [
          Container(
            height: previewBoxHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.background(context).withOpacity(.72),
                  accent.withOpacity(.10),
                  AppColors.background(context).withOpacity(.92),
                ],
              ),
              border: Border.all(color: accent.withOpacity(.22)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // خط جاده فرضی زیر خودرو: نشان می‌دهد مکان‌نما همیشه
                // در امتداد جاده می‌نشیند (نه عمود بر آن).
                Positioned(
                  bottom: 24,
                  left: 40,
                  right: 40,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(.28),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                settings.activeTab == AppearanceTab.car
                    ? CarMarker3D(
                        key: ValueKey(
                            'preview-car-${settings.vehicleModelIndex}'),
                        size: previewCarSize,
                        modelIndex: settings.vehicleModelIndex,
                        // headingDeg=0 یعنی جلوی خودرو با خط جادهٔ
                        // افقی هم‌راستاست.
                        headingDeg: 0,
                        // پیش‌نمایش تنظیمات عمداً از نمای کاملاً بالا شروع
                        // می‌شود و با همان اسلایدر به نمای پشت خودرو می‌رود.
                        cameraAngleDegrees: settings.vehicleViewAngleDegrees,
                        sizePercent: settings.carSizePercent,
                        // interactive=false تا لمسِ داخلِ پیش‌نمایش
                        // هیچ چرخشی روی مدل ایجاد نکند.
                        interactive: false,
                      )
                    : Stack(
                        key: const ValueKey('preview-pin'),
                        alignment: Alignment.center,
                        children: [
                          GpsLocationDot(size: 16),
                          NavArrow(
                            size: 86,
                            color: settings.pinColor,
                            glow: settings.pinShadowEnabled,
                          ),
                        ],
                      ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.get(
              context,
              ref,
              settings.activeTab == AppearanceTab.car
                  ? 'marker_vehicle_preview_label'
                  : 'marker_arrow_preview_label',
            ),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.onCustom,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in colors)
          _ColorDot(
            color: color,
            selected: selected.toARGB32() == color.toARGB32(),
            onTap: () => onSelected(color),
          ),
        _RainbowDot(onTap: onCustom),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Semantics(
      button: true,
      label: AppStrings.literal('رنگ'),
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: selected ? 52 : 44,
          height: selected ? 52 : 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? accent : AppColors.glassBorder(context),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: accent.withOpacity(.35), blurRadius: 12)]
                : null,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white.withOpacity(.25)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RainbowDot extends StatelessWidget {
  const _RainbowDot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder(context)),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFFE84B4B),
                  Color(0xFFF4B942),
                  Color(0xFF62C554),
                  Color(0xFF41B6E6),
                  Color(0xFF7F55D9),
                  Color(0xFFE84B4B),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withOpacity(.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(.38)),
              ),
              child: Text(
                '${value.round()}$suffix',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withOpacity(.18),
            thumbColor: accent,
            overlayColor: accent.withOpacity(.12),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _AngleSlider extends StatelessWidget {
  const _AngleSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withOpacity(.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(.38)),
              ),
              child: Text(
                '${value.round()}°',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            Text(
              AppStrings.literal('نمایش خودرو · بالا ← پشت'),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withOpacity(.18),
            thumbColor: accent,
            overlayColor: accent.withOpacity(.12),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.clamp(0, 90).toDouble(),
            min: 0,
            max: 90,
            divisions: 9,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppStrings.literal('نمای از بالا'),
                style: _hintStyle(context)),
            Text(AppStrings.literal('نمای پشت'), style: _hintStyle(context)),
          ],
        ),
      ],
    );
  }

  TextStyle _hintStyle(BuildContext context) => TextStyle(
        color: AppColors.textMuted(context),
        fontSize: 11,
      );
}

class _SettingCaption extends StatelessWidget {
  const _SettingCaption(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          AppStrings.literal(label),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background(context).withOpacity(.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder(context)),
        ),
        child: Row(
          children: [
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: color,
            ),
            const Spacer(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.textMuted(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, color: color, size: 20),
          ],
        ),
      );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return IconButton(
      onPressed: onTap,
      tooltip: AppStrings.literal('تغییر مدل'),
      icon: Icon(icon, color: accent, size: 28),
      style: IconButton.styleFrom(
        backgroundColor: accent.withOpacity(.10),
        side: BorderSide(color: accent.withOpacity(.5)),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.glassPanelSoft(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                        iconColor == Colors.transparent
                            ? Icons.circle
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted(context),
                        size: 22),
                    const Spacer(),
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(width: 9),
                    Icon(icon, color: iconColor, size: 25),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.glassBorder(context), height: 1),
                const SizedBox(height: 13),
                child,
              ],
            ),
          ),
        ),
      );
}

class _CustomColorDialog extends StatelessWidget {
  const _CustomColorDialog({required this.selected});
  final Color selected;

  static const colors = <Color>[
    Color(0xFF8A3FD0),
    Color(0xFFB45CFF),
    Color(0xFF4A22A8),
    Color(0xFF2F6FE0),
    Color(0xFF39C2E7),
    Color(0xFF1FAE8A),
    Color(0xFF65B52E),
    Color(0xFFF0B719),
    Color(0xFFFF8C42),
    Color(0xFFD92531),
    Color(0xFFE84B87),
    Color(0xFFFFFFFF),
    Color(0xFFB9BEC8),
    Color(0xFF5C6470),
    Color(0xFF20242C),
    Color(0xFF080A0E),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppColors.frameBackground(context),
        title: Text(AppStrings.literal('انتخاب رنگ سفارشی')),
        content: SizedBox(
          width: 280,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: colors.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final color = colors[index];
              final isSelected = color.toARGB32() == selected.toARGB32();
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(color),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryAccent(context)
                          : AppColors.glassBorder(context),
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
}
