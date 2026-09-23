import 'dart:math' as math;
import 'dart:ui';
import '../../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/app_settings_providers.dart'
    show appColorPresets;
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/page_header.dart';
import 'appearance/shared_widgets.dart';
import 'appearance_settings_providers.dart';

String _toHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}';

Color _lighten(Color c, double amount) =>
    Color.lerp(c, Colors.white, amount) ?? c;

/// صفحهٔ «تنظیمات مسیر»: ظاهر خط مسیر روی نقشه، محدودیت‌ها و
/// نوع مسیر ترجیحی، با هدر مشترک و رنگ پویا.
class RouteSettingsScreen extends ConsumerWidget {
  const RouteSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
        title: AppStrings.literal('تنظیمات مسیر'),
        subtitle: AppStrings.literal('ظاهر مسیر و گزینه‌های مسیریابی'),
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
            Positioned.fill(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _RoutePreviewCard(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
                      children: const [
                        _RouteStyleCard(),
                        SizedBox(height: 20),
                        _SectionHeader('پرهیز از'),
                        SizedBox(height: 10),
                        _AvoidRow(),
                        SizedBox(height: 20),
                        _SectionHeader('نوع مسیر'),
                        SizedBox(height: 10),
                        _RouteTypeRow(),
                        SizedBox(height: 20),
                        _RouteTogglesCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const BottomNav(currentPage: NavKey.settings),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// اجزای مشترکِ این صفحه.
// ============================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          AppStrings.literal(text),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
          ),
        ),
      );
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          AppStrings.literal(text),
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.textMuted(context), fontSize: 11.5),
        ),
      );
}

class _GlassCard extends StatelessWidget {
  const _GlassCard(
      {this.title, this.icon, this.iconColor, required this.child});
  final String? title;
  final IconData? icon;
  final Color? iconColor;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        title!,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (iconColor ?? AppColors.primaryAccent(context))
                              .withOpacity(0.18),
                        ),
                        child: Icon(icon, color: iconColor, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                ],
                child,
              ],
            ),
          ),
        ),
      );
}

/// سطرِ عمومی: آیکون + عنوان + زیرعنوان، با کنترلِ اختیاریِ leading
/// (چپ‌ترین عنصر) و محتوای اختیاریِ below (مثلاً اسلایدر یا انتخاب‌گر).
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.leading,
    this.below,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: iconColor.withOpacity(0.16)),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (below != null) ...[const SizedBox(height: 10), below!],
        ],
      );
}

/// اسلایدرِ برچسب‌دار با «کم» / «زیاد» (یا هر برچسبِ دیگر) دو سرِ آن —
/// همیشه چپ‌به‌راست، مستقل از جهتِ زبان، تا جهتِ افزایشِ مقدار گنگ نشود.
class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.minLabel = 'کم',
    this.maxLabel = 'زیاد',
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String minLabel;
  final String maxLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                inactiveTrackColor: accent.withOpacity(0.18),
                thumbColor: accent,
                overlayColor: accent.withOpacity(0.12),
                trackHeight: 4,
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                onChanged: enabled ? onChanged : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AppStrings.literal(minLabel),
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 11.5)),
                  Text(AppStrings.literal(maxLabel),
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// پیش‌نمایشِ نقشه — رنگ، ضخامت، نوعِ خط و شدتِ نئون واقعاً از
// [AppearanceSettings] خوانده می‌شوند تا با تغییرِ هر کدام از
// تنظیماتِ زیر، همین‌جا هم بلافاصله منعکس شود.
// ============================================================

class _RoutePreviewCard extends ConsumerWidget {
  const _RoutePreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final routeColor = _hexToColor(appearance.routeColorHex);
    final accent = AppColors.primaryAccent(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D13),
          border: Border.all(color: AppColors.glassBorder(context), width: 0.7),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            Offset at(double fx, double fy) => Offset(w * fx, h * fy);
            const originF = Offset(0.19, 0.55);
            const destF = Offset(0.82, 0.30);
            return Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _FakeMapPainter())),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RoutePathPainter(
                      color: routeColor,
                      origin: originF,
                      dest: destF,
                      strokeWidth: appearance.routeWidth,
                      lineStyle: appearance.routeLineStyle,
                      glowEnabled: appearance.routeGlowEnabled,
                      glowIntensity: appearance.routeGlowIntensity,
                    ),
                  ),
                ),
                for (final e in const [
                  MapEntry('کرج', Offset(0.15, 0.13)),
                  MapEntry('پردیس', Offset(0.87, 0.11)),
                  MapEntry('شهریار', Offset(0.09, 0.72)),
                  MapEntry('تهران', Offset(0.5, 0.63)),
                  MapEntry('ورامین', Offset(0.63, 0.86)),
                ])
                  Positioned(
                    left: at(e.value.dx, e.value.dy).dx - 24,
                    top: at(e.value.dx, e.value.dy).dy - 8,
                    child: Text(
                      AppStrings.literal(e.key),
                      style: const TextStyle(
                          color: Color(0xBFEAEAF2),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                Positioned(
                  left: at(originF.dx, originF.dy).dx - 16,
                  top: at(originF.dx, originF.dy).dy - 16,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A0D13),
                      border: Border.all(color: accent, width: 2.4),
                    ),
                    child:
                        Icon(Icons.navigation_rounded, color: accent, size: 15),
                  ),
                ),
                Positioned(
                  left: at(destF.dx, destF.dy).dx - 14,
                  top: at(destF.dx, destF.dy).dy - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.18),
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: const Icon(Icons.flag_rounded,
                        color: Colors.white, size: 13),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      _MapChip(icon: Icons.add_rounded),
                      const SizedBox(height: 6),
                      _MapChip(icon: Icons.remove_rounded),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.subGlassBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.subGlassBorder(context)),
                    ),
                    child: Text(
                      AppStrings.literal('پیش‌نمایش مسیر'),
                      style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.subGlassBg(context),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.subGlassBorder(context)),
        ),
        child: Icon(icon, size: 16, color: AppColors.textSecondary(context)),
      );
}

class _FakeMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 26) {
      canvas.drawLine(Offset(x, 0), Offset(x - 40, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 10), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePathPainter extends CustomPainter {
  const _RoutePathPainter({
    required this.color,
    required this.origin,
    required this.dest,
    this.strokeWidth = 3.4,
    this.lineStyle = RouteLineStyle.solid,
    this.glowEnabled = true,
    this.glowIntensity = 0.4,
  });
  final Color color;
  final Offset origin;
  final Offset dest;
  final double strokeWidth;
  final RouteLineStyle lineStyle;
  final bool glowEnabled;
  final double glowIntensity;

  // مقیاسِ ضخامتِ واقعیِ مسیر (که برای رندرِ روی نقشه با زوم بالا
  // طراحی شده، معمولاً ۴ تا ۲۲) به ابعادِ کوچکِ همین کارتِ پیش‌نمایش.
  double get _previewStrokeWidth => (strokeWidth * 0.42).clamp(1.6, 7.0);

  void _drawStyledPath(Canvas canvas, Path path, Paint paint) {
    switch (lineStyle) {
      case RouteLineStyle.solid:
        canvas.drawPath(path, paint);
        return;
      case RouteLineStyle.dotted:
        _drawDashed(canvas, path, paint, [0.1, 5.5], asDots: true);
        return;
      case RouteLineStyle.dashed:
        _drawDashed(canvas, path, paint, [11, 8]);
        return;
      case RouteLineStyle.dotDash:
        _drawDashed(canvas, path, paint, [11, 6, 0.1, 6], asDots: false);
        return;
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint, List<double> pattern,
      {bool asDots = false}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      var patternIndex = 0;
      while (distance < metric.length) {
        final segmentLength = pattern[patternIndex % pattern.length];
        final draw = patternIndex.isEven;
        final end = math.min(distance + segmentLength, metric.length);
        if (draw) {
          if (asDots || segmentLength < 1) {
            final tangent = metric.getTangentForOffset(distance);
            if (tangent != null) {
              canvas.drawCircle(tangent.position, paint.strokeWidth / 2,
                  paint..style = PaintingStyle.fill);
              paint.style = PaintingStyle.stroke;
            }
          } else {
            final extract = metric.extractPath(distance, end);
            canvas.drawPath(extract, paint);
          }
        }
        distance = end;
        patternIndex++;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset f) => Offset(size.width * f.dx, size.height * f.dy);
    final bends = [
      origin,
      const Offset(0.30, 0.28),
      const Offset(0.45, 0.35),
      const Offset(0.60, 0.20),
      dest,
    ].map(at).toList();

    final path = Path()..moveTo(bends.first.dx, bends.first.dy);
    for (var i = 1; i < bends.length; i++) {
      final prev = bends[i - 1];
      final curr = bends[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(bends.last.dx, bends.last.dy);

    if (glowEnabled && glowIntensity > 0) {
      final glow = Paint()
        ..color = color.withOpacity(0.35 * glowIntensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _previewStrokeWidth + 6 * glowIntensity
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 4 * glowIntensity);
      _drawStyledPath(canvas, path, glow);
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _previewStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawStyledPath(canvas, path, line);

    final dot = Paint()..color = Colors.white.withOpacity(0.85);
    for (final b in bends.sublist(1, bends.length - 1)) {
      canvas.drawCircle(b, 2.6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePathPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.lineStyle != lineStyle ||
      oldDelegate.glowEnabled != glowEnabled ||
      oldDelegate.glowIntensity != glowIntensity;
}

// ============================================================
// کارتِ ظاهرِ مسیر: رنگ، ضخامت، نوع خط، حالت نئونی.
// ============================================================

class _RouteStyleCard extends ConsumerWidget {
  const _RouteStyleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final notifier = ref.read(appearanceSettingsProvider.notifier);
    final currentHex = appearance.routeColorHex.toLowerCase();
    final isCustom =
        !appColorPresets.any((c) => _toHex(c).toLowerCase() == currentHex);

    Future<void> setColor(Color c) => notifier.update((s) => s.copyWith(
          routeColorHex: _toHex(c),
          routeColorGlowHex: _toHex(_lighten(c, 0.18)),
        ));

    const lineStyles = [
      (RouteLineStyle.solid, 'پیوسته'),
      (RouteLineStyle.dotted, 'نقطه‌ای'),
      (RouteLineStyle.dashed, 'خط‌چین'),
      (RouteLineStyle.dotDash, 'نقطه‌خط'),
    ];

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            icon: Icons.palette_rounded,
            iconColor: const Color(0xFFB57BFF),
            title: AppStrings.literal('رنگ مسیر'),
            subtitle: AppStrings.literal('رنگ خطوط مسیر روی نقشه'),
            below: Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in appColorPresets)
                    AppColorSwatch(
                      color: c,
                      selected:
                          !isCustom && _toHex(c).toLowerCase() == currentHex,
                      onTap: () => setColor(c),
                    ),
                  RainbowSwatch(
                    selected: isCustom,
                    onTap: () async {
                      final picked = await ColorPickerSheet.show(
                          context, _hexToColor(appearance.routeColorHex));
                      if (picked != null) await setColor(picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          const RowDivider(),
          _Row(
            icon: Icons.graphic_eq_rounded,
            iconColor: const Color(0xFF5CC8FF),
            title: AppStrings.literal('ضخامت مسیر'),
            subtitle: AppStrings.literal('ضخامت خطوط مسیر روی نقشه'),
            below: _LabeledSlider(
              value: appearance.routeWidth,
              min: 2,
              max: 18,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(routeWidth: v)),
            ),
          ),
          const RowDivider(),
          _Row(
            icon: Icons.route_rounded,
            iconColor: const Color(0xFFF2A93C),
            title: AppStrings.literal('نوع خط مسیر'),
            subtitle: AppStrings.literal('ظاهر خط مسیر روی نقشه'),
            below: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  for (final style in lineStyles) ...[
                    Expanded(
                      child: _LineStyleBox(
                        style: style.$1,
                        label: style.$2,
                        selected: appearance.routeLineStyle == style.$1,
                        onTap: () => notifier.update(
                            (s) => s.copyWith(routeLineStyle: style.$1)),
                      ),
                    ),
                    if (style != lineStyles.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const RowDivider(),
          _Row(
            icon: Icons.auto_awesome_rounded,
            iconColor: const Color(0xFF8FD14F),
            title: AppStrings.literal('حالت نئونی'),
            subtitle: AppStrings.literal('روشن‌کردن افکتِ نئونی برای مسیر'),
            leading: Switch.adaptive(
              value: appearance.routeGlowEnabled,
              activeColor: AppColors.primaryAccent(context),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(routeGlowEnabled: v)),
            ),
            below: _LabeledSlider(
              value: appearance.routeGlowIntensity,
              minLabel: 'کم',
              maxLabel: 'شدید',
              enabled: appearance.routeGlowEnabled,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(routeGlowIntensity: v)),
            ),
          ),
        ],
      ),
    );
  }
}

Color _hexToColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

class _LineStyleBox extends StatelessWidget {
  const _LineStyleBox({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final RouteLineStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.14)
                : AppColors.surfaceMuted(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? accent : Colors.transparent, width: 1.4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(40, 10),
                painter: _LineStyleSamplePainter(
                    style: style,
                    color:
                        selected ? accent : AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.literal(label),
                style: TextStyle(
                  color: selected ? accent : AppColors.textSecondary(context),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineStyleSamplePainter extends CustomPainter {
  const _LineStyleSamplePainter({required this.style, required this.color});
  final RouteLineStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    switch (style) {
      case RouteLineStyle.solid:
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        break;
      case RouteLineStyle.dotted:
        for (double x = 1; x < size.width; x += 6) {
          canvas.drawCircle(Offset(x, y), 1.1, paint);
        }
        break;
      case RouteLineStyle.dashed:
        for (double x = 0; x < size.width; x += 9) {
          canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        }
        break;
      case RouteLineStyle.dotDash:
        double x = 0;
        var toggle = true;
        while (x < size.width) {
          if (toggle) {
            canvas.drawLine(Offset(x, y), Offset(x + 7, y), paint);
            x += 10;
          } else {
            canvas.drawCircle(Offset(x, y), 1.1, paint);
            x += 5;
          }
          toggle = !toggle;
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LineStyleSamplePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}

// ============================================================
// پرهیز از.
// ============================================================

class _AvoidRow extends ConsumerWidget {
  const _AvoidRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final notifier = ref.read(appearanceSettingsProvider.notifier);

    final items = [
      (
        Icons.toll_rounded,
        'عوارضی',
        const Color(0xFFE0973F),
        appearance.avoidTolls,
        (bool v) => notifier.update((s) => s.copyWith(avoidTolls: v)),
      ),
      (
        Icons.terrain_rounded,
        'جاده خاکی',
        const Color(0xFFB0703F),
        appearance.avoidUnpavedRoads,
        (bool v) => notifier.update((s) => s.copyWith(avoidUnpavedRoads: v)),
      ),
      (
        Icons.add_road_rounded,
        'آزادراه',
        const Color(0xFF5CC8FF),
        appearance.avoidHighways,
        (bool v) => notifier.update((s) => s.copyWith(avoidHighways: v)),
      ),
      (
        Icons.directions_car_filled_rounded,
        'اوج ترافیک',
        const Color(0xFF8FD14F),
        appearance.avoidTraffic,
        (bool v) => notifier.update((s) => s.copyWith(avoidTraffic: v)),
      ),
      (
        Icons.directions_ferry_rounded,
        'کشتی و قطار',
        const Color(0xFFE0523F),
        appearance.avoidFerries,
        (bool v) => notifier.update((s) => s.copyWith(avoidFerries: v)),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final item in items) ...[
              _AvoidCard(
                icon: item.$1,
                label: item.$2,
                color: item.$3,
                value: item.$4,
                onChanged: (v) => item.$5(v),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvoidCard extends StatelessWidget {
  const _AvoidCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(AppStrings.literal(label),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 8),
            Switch.adaptive(
                value: value, onChanged: onChanged, activeColor: color),
          ],
        ),
      );
}

// ============================================================
// نوع مسیر.
// ============================================================

class _RouteTypeRow extends ConsumerWidget {
  const _RouteTypeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final notifier = ref.read(appearanceSettingsProvider.notifier);

    final items = [
      (
        RoutePlanningMode.economic,
        Icons.savings_rounded,
        'اقتصادی ترین',
        'صرفه‌جویی در مصرف سوخت',
        const Color(0xFF2E9E5B),
      ),
      (
        RoutePlanningMode.shortest,
        Icons.stars_rounded,
        'بهینه ترین',
        'تعادل زمان و هزینه',
        const Color(0xFF8A3FD0),
      ),
      (
        RoutePlanningMode.fastest,
        Icons.rocket_launch_rounded,
        'سریعترین',
        'کمترین زمان سفر',
        const Color(0xFF2F6FE0),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          for (final item in items) ...[
            Expanded(
              child: _RouteTypeCard(
                icon: item.$2,
                title: item.$3,
                subtitle: item.$4,
                color: item.$5,
                selected: appearance.routePlanningMode == item.$1,
                onTap: () => notifier
                    .update((s) => s.copyWith(routePlanningMode: item.$1)),
              ),
            ),
            if (item != items.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _RouteTypeCard extends StatelessWidget {
  const _RouteTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(selected ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color, width: selected ? 1.6 : 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color, size: 20),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 1.6),
                        color: selected ? color : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(Icons.circle,
                              color: Colors.white, size: 6)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(AppStrings.literal(title),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
                const SizedBox(height: 3),
                Text(
                  AppStrings.literal(subtitle),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.65), fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      );
}

// ============================================================
// سوییچ‌های نهایی.
// ============================================================

class _RouteTogglesCard extends ConsumerWidget {
  const _RouteTogglesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final notifier = ref.read(appearanceSettingsProvider.notifier);

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            icon: Icons.traffic_rounded,
            iconColor: const Color(0xFF8FD14F),
            title: AppStrings.literal('نمایش ترافیک لحظه‌ای'),
            subtitle: AppStrings.literal('نمایش رنگ ترافیک روی مسیر'),
            leading: Switch.adaptive(
              value: appearance.showLiveTraffic,
              activeColor: AppColors.primaryAccent(context),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(showLiveTraffic: v)),
            ),
          ),
          const RowDivider(),
          _Row(
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFF2A93C),
            title: AppStrings.literal('نمایش هشدارها روی مسیر'),
            subtitle: AppStrings.literal('نمایش دوربین، خطرات و محدودیت‌ها'),
            leading: Switch.adaptive(
              value: appearance.showRouteWarnings,
              activeColor: AppColors.primaryAccent(context),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(showRouteWarnings: v)),
            ),
          ),
          const RowDivider(),
          _Row(
            icon: Icons.compare_arrows_rounded,
            iconColor: const Color(0xFF5CC8FF),
            title: AppStrings.literal('مسیر جایگزین خودکار'),
            subtitle: AppStrings.literal(
                'در صورت ترافیک شدید، مسیر دیگر پیشنهاد شود'),
            leading: Switch.adaptive(
              value: appearance.autoRerouteEnabled,
              activeColor: AppColors.primaryAccent(context),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(autoRerouteEnabled: v)),
            ),
          ),
        ],
      ),
    );
  }
}
