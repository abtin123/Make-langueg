import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/settings/domain/appearance_settings.dart';
import '../../features/routing/presentation/roundabout_dynamic.dart';

@immutable
class RouteGuidanceCardData {
  const RouteGuidanceCardData({
    required this.icon,
    required this.distanceText,
    required this.streetText,
    required this.etaLabel,
    required this.etaValue,
    required this.remainingLabel,
    required this.remainingValue,
    required this.durationLabel,
    required this.durationValue,
    this.onClose,
    this.iconWidget,
    this.iconScale = 1.0,
  });

  final IconData icon;
  final String distanceText;
  final String streetText;
  final String etaLabel;
  final String etaValue;
  final String remainingLabel;
  final String remainingValue;
  final String durationLabel;
  final String durationValue;
  final VoidCallback? onClose;
  final Widget? iconWidget;
  /// ضریب مستقل اندازهٔ آیکون سفارشی. برای پیکان معمولی از تنظیم «اندازه فلش»
  /// می‌آید؛ آیکون میدان اندازهٔ داخلی خودش را از style می‌گیرد و ۱ می‌ماند.
  final double iconScale;
}

/// Flutter implementation of preview(1).html's navigation card.
///
/// The HTML is the geometry contract: 1110x260 card, with the original
/// 1214x1296 design coordinates preserved as the *layout*. Every visual
/// property (size, colors, opacity, corner radius, glow) is driven by
/// [AppearanceSettings] so the card is fully configurable from the
/// appearance settings screen; only the relative positions of its
/// elements stay pixel-locked to the original design.
class RouteGuidanceCard extends StatelessWidget {
  const RouteGuidanceCard({super.key, required this.settings, required this.data});

  final AppearanceSettings settings;
  final RouteGuidanceCardData data;

  /// اسلایدرهای ۰..۱ را به ضریبِ اندازه‌ای در بازهٔ منطقی تبدیل می‌کند تا
  /// مقدارِ پیش‌فرضِ ۰.۵ دقیقاً برابرِ ضریبِ ۱ (بدون تغییر نسبت به طراحیِ
  /// اصلی) باشد.
  static double _sizeFactor(double v, {double min = 0.7, double max = 1.3}) =>
      min + (v.clamp(0.0, 1.0)) * (max - min);

  @override
  Widget build(BuildContext context) {
    final heightFactor = _sizeFactor(settings.routeCardHeight, min: 0.75, max: 1.55);
    final arrowFactor = _sizeFactor(settings.routeCardArrowSize);
    final distanceFontFactor = _sizeFactor(settings.routeCardDistanceFontSize);
    final streetFontFactor = _sizeFactor(settings.routeCardStreetFontSize);
    final statsFontFactor = _sizeFactor(settings.routeCardStatsFontSize);
    final arrowThicknessExtra = (settings.routeCardArrowThickness - 0.72) * 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / 1110.0;
        final w = 1110.0 * scale;

        // ارتفاع کارت فقط از تنظیم «ارتفاع کارت» می‌آید. فونت‌ها حق ندارند
        // بدنه را خودکار بلند کنند؛ برای جلوگیری از بیرون‌زدگی، محتوا در
        // همان قاب scale/ellipsis می‌شود.
        final distanceContentHeight = math.max(64.0, 48.0 + 34.0 * distanceFontFactor);
        final streetContentHeight = math.max(74.0, 56.0 * streetFontFactor + 18.0);
        final statsContentHeight = math.max(68.0, 34.0 * statsFontFactor + 30.0);
        final requestedHeight = 260.0 * heightFactor;
        final h = requestedHeight * scale;
        final contentScale = (requestedHeight / 260.0).clamp(0.72, 1.0);

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: _HtmlCardBackground(
                  backgroundColor: settings.routeCardBackgroundColor,
                  borderColor: settings.routeCardBorderColor,
                  glowColor: settings.routeCardGlowColor,
                  opacity: settings.routeCardOpacity,
                  cornerRadius: settings.routeCardCornerRadius * 110.0,
                  glowIntensity: settings.routeCardGlowIntensity,
                ),
              ),

              // --- ستون چپ: فلش مانور + عددِ فاصله دقیقاً زیرِ آن ---
              Positioned(
                left: 18.0 * scale,
                top: 30.0 * scale,
                width: 292.0 * scale,
                height: 148.0 * scale,
                child: Center(
                  child: () {
                    final custom = data.iconWidget;
                    if (custom != null) {
                      return Transform.scale(
                        scale: data.iconScale.clamp(0.55, 1.45).toDouble(),
                        child: SizedBox(
                          width: 150 * scale,
                          height: 150 * scale,
                          child: custom,
                        ),
                      );
                    }
                    return SizedBox(
                      width: 148.0 * scale * arrowFactor,
                      height: 148.0 * scale * arrowFactor,
                      child: _TurnArrowGlyph(
                        icon: data.icon,
                        color: settings.routeCardArrowColor,
                        strokeExtra: arrowThicknessExtra,
                      ),
                    );
                  }(),
                ),
              ),
              Positioned(
                left: 18.0 * scale,
                top: (180.0 * contentScale) * scale,
                width: 292.0 * scale,
                height: distanceContentHeight * contentScale * scale,
                child: _HtmlText(
                  data.distanceText,
                  family: 'Poppins',
                  size: 62 * distanceFontFactor,
                  weight: FontWeight.w700,
                  color: settings.routeCardDistanceColor,
                  align: TextAlign.center,
                ),
              ),

              // جداکنندهٔ عمودیِ بلند، بینِ ستونِ فلش و ستونِ متن/آمار.
              Positioned(
                left: 328.0 * scale,
                top: 55.0 * scale,
                child: _HtmlDivider(scale: scale, color: settings.routeCardBorderColor, height: 150),
              ),

              // --- ستون راست: دستور مسیر ---
              // دکمهٔ بستن عمداً از این ناحیه خارج شده تا کل عرضِ بالا برای
              // متنِ مانور آزاد باشد. متن نیز حداکثر دو خط دارد و در صورت
              // طولانی بودن، با ellipsis جمع می‌شود؛ کوچک‌کردن افراطیِ فونت
              // برای جا دادن جمله‌های بی‌نهایت طولانی دیگر انجام نمی‌شود.
              Positioned(
                left: 356.0 * scale,
                top: (44.0 * contentScale) * scale,
                width: 620.0 * scale,
                height: math.max(82.0, streetContentHeight) * contentScale * scale,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: _HtmlText(
                    data.streetText,
                    family: 'Vazirmatn',
                    size: 56 * streetFontFactor,
                    weight: FontWeight.w600,
                    color: settings.routeCardStreetColor,
                    align: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              // خطِ افقیِ جداکننده، درست زیرِ متنِ مانور.
              Positioned(
                left: 356.0 * scale,
                top: (136.0 * contentScale) * scale,
                width: 620.0 * scale,
                height: 1.6 * scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        settings.routeCardBorderColor.withOpacity(0),
                        settings.routeCardBorderColor.withOpacity(.4),
                        settings.routeCardBorderColor.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),

              // ردیفِ آمار: رسیدن / باقی‌مانده / زمان — سه ستونِ مساوی با
              // آیکون، درست مطابقِ عکسِ مرجع. فیلدِ durationLabel/Value
              // پیش‌تر در مدلِ داده وجود داشت اما هیچ‌گاه رندر نمی‌شد.
              Positioned(
                left: 356.0 * scale,
                top: (151.0 * contentScale) * scale,
                width: 620.0 * scale,
                height: statsContentHeight * contentScale * scale,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _StatColumn(
                        icon: Icons.access_time_rounded,
                        iconIsRing: true,
                        label: data.etaLabel,
                        value: data.etaValue,
                        iconColor: settings.routeCardBorderColor,
                        labelColor: settings.routeCardStatsColor.withOpacity(
                          settings.routeCardStatsColor.opacity * .72,
                        ),
                        valueColor: settings.routeCardStatsColor,
                        labelFontSize: 22 * statsFontFactor,
                        valueFontSize: 34 * statsFontFactor,
                        scale: scale,
                      ),
                    ),
                    _StatDivider(scale: scale, color: settings.routeCardBorderColor),
                    Expanded(
                      child: _StatColumn(
                        icon: Icons.alt_route_rounded,
                        iconIsRing: false,
                        label: data.remainingLabel,
                        value: data.remainingValue,
                        iconColor: settings.routeCardBorderColor,
                        labelColor: settings.routeCardStatsColor.withOpacity(
                          settings.routeCardStatsColor.opacity * .72,
                        ),
                        valueColor: settings.routeCardStatsColor,
                        labelFontSize: 22 * statsFontFactor,
                        valueFontSize: 34 * statsFontFactor,
                        scale: scale,
                      ),
                    ),
                    _StatDivider(scale: scale, color: settings.routeCardBorderColor),
                    Expanded(
                      child: _StatColumn(
                        icon: Icons.access_time_rounded,
                        iconIsRing: true,
                        label: data.durationLabel,
                        value: data.durationValue,
                        iconColor: settings.routeCardBorderColor,
                        labelColor: settings.routeCardStatsColor.withOpacity(
                          settings.routeCardStatsColor.opacity * .72,
                        ),
                        valueColor: settings.routeCardStatsColor,
                        labelFontSize: 22 * statsFontFactor,
                        valueFontSize: 34 * statsFontFactor,
                        scale: scale,
                      ),
                    ),
                  ],
                ),
              ),

              if (data.onClose != null)
                Positioned(
                  // ضربدر کنار اطلاعات مسیر قرار می‌گیرد، نه کنار متن بالا؛
                  // بنابراین فضای بالای کارت برای دستور مسیر کاملاً آزاد است.
                  left: 988.0 * scale,
                  top: (166.0 * contentScale) * scale,
                  width: 92.0 * contentScale * scale,
                  height: 92.0 * contentScale * scale,
                  child: _HtmlCancelButton(onTap: data.onClose!, scale: scale),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HtmlCardBackground extends StatelessWidget {
  const _HtmlCardBackground({
    required this.backgroundColor,
    required this.borderColor,
    required this.glowColor,
    required this.opacity,
    required this.cornerRadius,
    required this.glowIntensity,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color glowColor;
  final double opacity;
  final double cornerRadius;
  final double glowIntensity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HtmlCardPainter(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        glowColor: glowColor,
        opacity: opacity,
        cornerRadius: cornerRadius,
        glowIntensity: glowIntensity,
      ),
    );
  }
}

class _HtmlCardPainter extends CustomPainter {
  _HtmlCardPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.glowColor,
    required this.opacity,
    required this.cornerRadius,
    required this.glowIntensity,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color glowColor;
  final double opacity;
  final double cornerRadius;
  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = cornerRadius * size.width / 1110.0;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(1.25), Radius.circular(radius));

    if (glowIntensity > 0) {
      final glow = Paint()
        ..color = glowColor.withOpacity((glowIntensity * .7).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (17.0 + glowIntensity * 26.0) * size.width / 1110.0,
        );
      canvas.drawRRect(rrect, glow);
    }

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          backgroundColor.withOpacity((opacity * 1.05).clamp(0.0, 1.0)),
          backgroundColor.withOpacity(opacity.clamp(0.0, 1.0)),
          backgroundColor.withOpacity((opacity * 1.05).clamp(0.0, 1.0)),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, fill);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * size.width / 1110.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          borderColor.withOpacity(.86),
          borderColor.withOpacity(.72),
          borderColor.withOpacity(.76),
          borderColor.withOpacity(.82),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, border);

    final highlight = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, borderColor.withOpacity(.82), Colors.transparent],
      ).createShader(Rect.fromLTWH(size.width * .22, 0, size.width * .56, 3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .22, 0, size.width * .56, 3 * size.width / 1110.0),
        const Radius.circular(3),
      ),
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _HtmlCardPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.glowColor != glowColor ||
      oldDelegate.opacity != opacity ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.glowIntensity != glowIntensity;
}

class _HtmlDivider extends StatelessWidget {
  const _HtmlDivider({required this.scale, required this.color, this.height = 146});
  final double scale;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 2 * scale,
        height: height * scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, color.withOpacity(.38), Colors.transparent],
            ),
          ),
        ),
      );
}

class _HtmlText extends StatelessWidget {
  const _HtmlText(
    this.text, {
    required this.family,
    required this.size,
    required this.weight,
    required this.color,
    required this.align,
    this.gradient,
    this.rtl = false,
    this.maxLines = 1,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final String family;
  final double size;
  final FontWeight weight;
  final Color color;
  final TextAlign align;
  final Gradient? gradient;
  final bool rtl;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: align,
      style: TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        height: 1,
        color: color,
      ),
    );
    final painted = gradient == null
        ? textWidget
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => gradient!.createShader(bounds),
            child: textWidget,
          );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
      child: painted,
    );
    return rtl ? Directionality(textDirection: TextDirection.rtl, child: child) : child;
  }
}

/// یک ستونِ آمار (رسیدن/باقی‌مانده/زمان): آیکون در سمت چپ، برچسب کوچک
/// بالا و مقدارِ بزرگ پایین — دقیقاً مطابقِ چیدمانِ عکسِ مرجع.
class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.icon,
    required this.iconIsRing,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.labelColor,
    required this.valueColor,
    required this.labelFontSize,
    required this.valueFontSize,
    required this.scale,
  });

  final IconData icon;
  final bool iconIsRing;
  final String label;
  final String value;
  final Color iconColor;
  final Color labelColor;
  final Color valueColor;
  final double labelFontSize;
  final double valueFontSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final iconBox = 32.0 * scale;
    final iconGlyph = iconIsRing
        ? Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: iconColor, width: 2.2 * scale),
            ),
            child: Icon(icon, color: iconColor, size: iconBox * .52),
          )
        : Icon(icon, color: iconColor, size: iconBox);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconGlyph,
          SizedBox(width: 9 * scale),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Vazirmatn',
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                    color: labelColor,
                  ),
                ),
              ),
              Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// جداکنندهٔ عمودیِ کوتاه بینِ سه ستونِ آمار (برخلافِ [_HtmlDivider] که
/// کل ارتفاعِ کارت را می‌پوشاند).
class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.scale, required this.color});
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1.4 * scale,
        height: 46 * scale,
        margin: EdgeInsets.symmetric(horizontal: 4 * scale),
        color: color.withOpacity(.32),
      );
}

class _HtmlCancelButton extends StatelessWidget {
  const _HtmlCancelButton({required this.onTap, required this.scale});
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final dot = 82.0 * scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-.16, -.4),
              colors: [Color(0xFFFF6676), Color(0xFFE11F3B), Color(0xFFB60F2D)],
              stops: [0, .72, 1],
            ),
            border: Border.all(color: const Color(0xEBFF8492), width: 3 * scale),
            boxShadow: [BoxShadow(color: const Color(0x9EFF2846), blurRadius: 28 * scale)],
          ),
          child: Icon(Icons.close_rounded, color: Colors.white, size: 38 * scale),
        ),
      ),
    );
  }
}

/// نسخهٔ گرادیانی/درخشانِ فلشِ مانور، دقیقاً مطابقِ عکسِ مرجع: آبیِ روشن
/// در بالا-چپ که به آبیِ پررنگ‌تر در پایین-راست می‌رود، با هالهٔ نرمِ دور
/// شکل. برخلافِ نسخهٔ قبلی، این‌جا viewBox دقیقاً روی محدودهٔ واقعیِ
/// مسیر (۰..۱۲۰) بسته می‌شود، پس فلش دیگر نصفه از بومِ SVG بیرون نمی‌زند.
String _turnGlyphSvg(
  IconData icon, {
  required Color color,
  required double strokeExtra,
}) {
  final d = _pathForIcon(icon);
  final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  final glowHex =
      '#${Color.lerp(color, Colors.white, .5)!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <defs>
    <linearGradient id="turnG" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="$glowHex"/><stop offset="1" stop-color="$hex"/></linearGradient>
    <filter id="turnGlow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <path d="$d" fill="url(#turnG)" stroke="$glowHex" stroke-width="${(2 + strokeExtra).toStringAsFixed(2)}" stroke-linejoin="round" filter="url(#turnGlow)"/>
</svg>''';
}

/// فلشِ پیش‌فرضِ کارت مسیریابی (برای مانورهای معمولی، نه میدان)، با
/// گرادیان و درخشش. جایگزینِ مستقیمِ overlay قدیمی است و همیشه داخلِ
/// یک جعبهٔ مربعیِ مشخص رندر می‌شود تا هرگز بریده یا جابه‌جا نشود.
class _TurnArrowGlyph extends StatelessWidget {
  const _TurnArrowGlyph({required this.icon, required this.color, required this.strokeExtra});
  final IconData icon;
  final Color color;
  final double strokeExtra;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        _turnGlyphSvg(icon, color: color, strokeExtra: strokeExtra),
        fit: BoxFit.contain,
      );
}

String _pathForIcon(IconData icon) {
  if (icon == Icons.turn_left_rounded || icon == Icons.turn_sharp_left_rounded || icon == Icons.turn_slight_left_rounded) {
    return 'M78 105V55Q78 38 61 38H42V24L16 48L42 72V58H56Q62 58 62 65V105Z';
  }
  if (icon == Icons.turn_right_rounded || icon == Icons.turn_sharp_right_rounded || icon == Icons.turn_slight_right_rounded) {
    return 'M42 105V55Q42 38 59 38H78V24L104 48L78 72V58H64Q58 58 58 65V105Z';
  }
  if (icon == Icons.u_turn_left_rounded) return 'M90 105V58Q90 30 62 30H44V16L18 40L44 64V48H58Q72 48 72 62V105Z';
  if (icon == Icons.u_turn_right_rounded) return 'M30 105V58Q30 30 58 30H76V16L102 40L76 64V48H62Q48 48 48 62V105Z';
  return 'M52 104V36H34L60 12L86 36H68V104Z';
}

class ManeuverArrowIcon extends StatelessWidget {
  const ManeuverArrowIcon({super.key, required this.modifier, this.color, this.thickness = .72});
  final String? modifier;
  final Color? color;
  final double thickness;

  String get _normalized => (modifier ?? 'straight').trim().toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ');
  bool get _right => _normalized.contains('right');
  bool get _uturn => _normalized.contains('uturn') || _normalized.contains('u turn');

  IconData get _icon {
    final m = _normalized;
    if (_uturn) return _right ? Icons.u_turn_right_rounded : Icons.u_turn_left_rounded;
    if (m == 'sharp left') return Icons.turn_sharp_left_rounded;
    if (m == 'sharp right') return Icons.turn_sharp_right_rounded;
    if (m == 'slight left') return Icons.turn_slight_left_rounded;
    if (m == 'slight right') return Icons.turn_slight_right_rounded;
    if (m == 'left') return Icons.turn_left_rounded;
    if (m == 'right') return Icons.turn_right_rounded;
    return Icons.straight_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final d = _pathForIcon(_icon);
    final c = color ?? const Color(0xFF43E6FF);
    final h = '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><path d="$d" fill="$h" stroke="$h" stroke-width="${2 + thickness}" stroke-linejoin="round"/></svg>',
      fit: BoxFit.contain,
    );
  }
}
