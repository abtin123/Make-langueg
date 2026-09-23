import 'package:flutter/material.dart';

class NavArrowPainter extends CustomPainter {
  final Color baseColor;
  final Color? lightColor;
  final Color? darkColor;
  final Color rimColor;
  final bool glow;

  const NavArrowPainter({
    this.baseColor = const Color(0xFFFF7A1A),
    this.lightColor,
    this.darkColor,
    this.rimColor = const Color(0xFFFFFFFF),
    this.glow = false,
  });

  Path _buildArrowPath(double w, double h) {
    final apex = Offset(w * 0.5, h * 0.04);
    final rightTip = Offset(w * 0.94, h * 0.86);
    final rightIn = Offset(w * 0.62, h * 0.62);
    final notch = Offset(w * 0.5, h * 0.50);
    final leftIn = Offset(w * 0.38, h * 0.62);
    final leftTip = Offset(w * 0.06, h * 0.86);

    final path = Path()..moveTo(apex.dx, apex.dy);
    path.quadraticBezierTo(w * 0.78, h * 0.42, rightTip.dx, rightTip.dy);
    path.quadraticBezierTo(w * 0.86, h * 0.92, rightIn.dx, rightIn.dy);
    path.quadraticBezierTo(notch.dx, notch.dy + h * 0.10, notch.dx, notch.dy);
    path.quadraticBezierTo(notch.dx, notch.dy + h * 0.10, leftIn.dx, leftIn.dy);
    path.quadraticBezierTo(w * 0.14, h * 0.92, leftTip.dx, leftTip.dy);
    path.quadraticBezierTo(w * 0.22, h * 0.42, apex.dx, apex.dy);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outer = _buildArrowPath(w, h);
    final apex = Offset(w * 0.5, h * 0.04);
    final notch = Offset(w * 0.5, h * 0.52);

    final light = lightColor ?? Color.lerp(baseColor, Colors.white, 0.55)!;
    final mid = baseColor;
    final dark =
        darkColor ?? Color.lerp(baseColor, const Color(0xFFB33D00), 0.55)!;

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.92), width: w * 0.7, height: h * 0.14),
      Paint()
        ..color = mid.withOpacity(0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.08),
    );

    if (glow) {
      final glowPaint = Paint()
        ..color = mid.withOpacity(0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.16);
      canvas.drawPath(outer, glowPaint);
    }

    canvas.save();
    canvas.clipPath(outer);
    final leftHalf = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(0, h)
      ..lineTo(0, 0)
      ..close();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [light, mid],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    final rightMask = Path()
      ..moveTo(apex.dx, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(apex.dx, h)
      ..close();
    canvas.clipPath(rightMask);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mid, dark],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.restore();

    canvas.drawLine(
      apex,
      notch,
      Paint()
        ..strokeWidth = w * 0.02
        ..color = Colors.black.withOpacity(0.22)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      apex,
      notch,
      Paint()
        ..strokeWidth = w * 0.007
        ..color = Colors.white.withOpacity(0.55)
        ..strokeCap = StrokeCap.round,
    );

    final highlight = Path()
      ..moveTo(apex.dx - w * 0.03, apex.dy + h * 0.10)
      ..lineTo(w * 0.20, h * 0.56)
      ..lineTo(w * 0.28, h * 0.60)
      ..lineTo(apex.dx + w * 0.02, apex.dy + h * 0.20)
      ..close();
    canvas.drawPath(
      highlight,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.7),
            Colors.white.withOpacity(0.0)
          ],
        ).createShader(highlight.getBounds()),
    );

    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..strokeJoin = StrokeJoin.round
        ..color = mid.withOpacity(0.45),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeJoin = StrokeJoin.round
        ..color = rimColor.withOpacity(0.9),
    );
  }

  @override
  bool shouldRepaint(covariant NavArrowPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor ||
        oldDelegate.lightColor != lightColor ||
        oldDelegate.darkColor != darkColor ||
        oldDelegate.rimColor != rimColor ||
        oldDelegate.glow != glow;
  }
}

/// نقطهٔ ثابت موقعیت GPS که زیر پیکان نمایش داده می‌شود؛ بدون سایه و glow.
class GpsLocationDot extends StatelessWidget {
  const GpsLocationDot({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF4285F4),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class NavArrow extends StatelessWidget {
  final double size;
  final Color color;
  final bool glow;

  const NavArrow({
    super.key,
    this.size = 56,
    this.color = const Color(0xFFFF7A1A),
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    // عکس اصلی سفید/نقره‌ای و کم‌اشباع است. BlendMode.color فقط رنگ‌مایه
    // می‌گیرد و روشناییِ خودِ عکس را نگه می‌دارد؛ روی پیکسل‌های تقریباً‌سفیدِ
    // این عکس، هر رنگی هم انتخاب شود نتیجه چیزی جز یک سفیدِ کم‌رنگ نبود —
    // یعنی پیکانِ واقعیِ روی نقشه عملاً هم‌رنگِ انتخاب کاربر دیده نمی‌شد.
    // BlendMode.modulate رنگ را مستقیماً در روشناییِ هر پیکسل ضرب می‌کند:
    // پیکسل‌های روشن دقیقاً رنگِ انتخابی می‌گیرند و سایه‌روشنِ خودِ عکس هم
    // حفظ می‌شود، پس پیکان واقعاً هم‌رنگِ رنگِ انتخابی دیده می‌شود.
    final Widget image = ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.modulate),
      child: Image.asset(
        'assets/images/nav_arrow.webp',
        width: size,
        height: size * 1.15,
        fit: BoxFit.contain,
      ),
    );

    if (!glow) {
      return SizedBox(width: size, height: size * 1.15, child: image);
    }

    return SizedBox(
      width: size,
      height: size * 1.15,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.55),
              blurRadius: size * 0.28,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
        child: image,
      ),
    );
  }
}
