import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/routing_service.dart';
import '../../../core/theme/app_colors.dart';

/// هشدارهای کوچکِ مسیر؛ فقط آیکون دارند و عمداً متن ندارند.
/// کارت‌ها بدون فاصله زیر هم قرار می‌گیرند. کارت اول تب مثلثی ندارد و
/// کارت‌های بعدی یک تب مثلثیِ توپر با همان رنگ پس‌زمینه و همان خط دور دارند.
class RoadAlertStack extends StatelessWidget {
  const RoadAlertStack({
    super.key,
    required this.alerts,
    this.sizePercent = 100,
  });

  final List<RouteAlert> alerts;
  final double sizePercent;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < alerts.length; i++)
          RoadAlertBadge(
            alert: alerts[i],
            sizePercent: sizePercent,
            showConnector: i > 0,
          ),
      ],
    );
  }
}

class RoadAlertBadge extends StatelessWidget {
  const RoadAlertBadge({
    super.key,
    required this.alert,
    this.sizePercent = 100,
    this.showConnector = false,
  });

  final RouteAlert alert;
  final double sizePercent;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final scale = (sizePercent / 100).clamp(.70, 1.30).toDouble();
    final side = 54.0 * scale;
    final iconSide = 31.0 * scale;
    final tabHeight = showConnector ? 9.0 * scale : 0.0;
    final panel = AppColors.glassPanelSoft(context);
    final border = AppColors.glassBorder(context);
    final accent = AppColors.primaryAccent(context);
    // Warning artwork keeps its own recognizable traffic-sign colors. The
    // app accent may style the card border/glow, but must never recolor the
    // warning symbol itself.
    final iconColor = switch (alert.type) {
      RouteAlertType.speedCamera => const Color(0xFF1E88E5),
      RouteAlertType.speedBump => const Color(0xFFFFB300),
      RouteAlertType.policeCheckpoint => const Color(0xFF1565C0),
      RouteAlertType.trafficLight => const Color(0xFFFFC107),
    };

    return SizedBox(
      width: side,
      height: side + tabHeight,
      child: CustomPaint(
        painter: _AlertCardPainter(
          background: panel,
          border: border,
          accent: accent,
          showConnector: showConnector,
          tabHeight: tabHeight,
          radius: 15.0 * scale,
        ),
        child: Padding(
          padding: EdgeInsets.only(top: tabHeight),
          child: Center(
            child: CustomPaint(
              size: Size.square(iconSide),
              painter: _RoadAlertPainter(
                type: alert.type,
                color: iconColor,
                accent: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertCardPainter extends CustomPainter {
  const _AlertCardPainter({
    required this.background,
    required this.border,
    required this.accent,
    required this.showConnector,
    required this.tabHeight,
    required this.radius,
  });

  final Color background;
  final Color border;
  final Color accent;
  final bool showConnector;
  final double tabHeight;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyTop = showConnector ? tabHeight : 0.0;
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, bodyTop, size.width, size.height - bodyTop),
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    final fill = Paint()..color = background;
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    if (showConnector) {
      final cx = size.width / 2;
      final triangle = Path()
        ..moveTo(cx - tabHeight * .82, bodyTop + .8)
        ..lineTo(cx, .8)
        ..lineTo(cx + tabHeight * .82, bodyTop + .8)
        ..close();
      canvas.drawPath(triangle, fill);
      canvas.drawPath(
        Path()
          ..moveTo(cx - tabHeight * .82, bodyTop + .8)
          ..lineTo(cx, .8)
          ..lineTo(cx + tabHeight * .82, bodyTop + .8),
        stroke,
      );
    }

    final glow = Paint()
      ..color = accent.withOpacity(.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rect.deflate(.5), glow);
    canvas.drawRRect(rect, fill);
    canvas.drawRRect(rect, stroke);
  }

  @override
  bool shouldRepaint(covariant _AlertCardPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.border != border ||
      oldDelegate.accent != accent ||
      oldDelegate.showConnector != showConnector ||
      oldDelegate.tabHeight != tabHeight ||
      oldDelegate.radius != radius;
}

class _RoadAlertPainter extends CustomPainter {
  const _RoadAlertPainter({
    required this.type,
    required this.color,
    required this.accent,
  });

  final RouteAlertType type;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case RouteAlertType.speedCamera:
        _camera(canvas, size);
      case RouteAlertType.speedBump:
        _bump(canvas, size);
      case RouteAlertType.policeCheckpoint:
        _police(canvas, size);
      case RouteAlertType.trafficLight:
        _traffic(canvas, size);
    }
  }

  Paint _line(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _camera(Canvas canvas, Size s) {
    final p = _line(s.width * .075);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          s.width * .14, s.height * .27, s.width * .72, s.height * .46),
      Radius.circular(s.width * .14),
    );
    canvas.drawRRect(body, Paint()..color = color.withOpacity(.12));
    canvas.drawRRect(body, p);
    canvas.drawLine(Offset(s.width * .27, s.height * .19),
        Offset(s.width * .73, s.height * .19), p);
    canvas.drawCircle(Offset(s.width * .5, s.height * .50), s.width * .16, p);
    canvas.drawCircle(Offset(s.width * .5, s.height * .50), s.width * .065,
        Paint()..color = color);
    canvas.drawCircle(Offset(s.width * .73, s.height * .33), s.width * .035,
        Paint()..color = accent);
  }

  void _bump(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    final base = s.height * .70;
    final path = Path()
      ..moveTo(s.width * .08, base)
      ..cubicTo(s.width * .20, s.height * .20, s.width * .80, s.height * .20,
          s.width * .92, base)
      ..lineTo(s.width * .92, s.height * .82)
      ..lineTo(s.width * .08, s.height * .82)
      ..close();
    canvas.drawPath(path, p);
    final highlight = Paint()
      ..color = Colors.white.withOpacity(.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .045
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(
          s.width * .20, s.height * .29, s.width * .60, s.height * .42),
      math.pi,
      math.pi,
      false,
      highlight,
    );
  }

  void _police(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    final shield = Path()
      ..moveTo(s.width * .16, s.height * .25)
      ..lineTo(s.width * .50, s.height * .10)
      ..lineTo(s.width * .84, s.height * .25)
      ..lineTo(s.width * .75, s.height * .67)
      ..quadraticBezierTo(
          s.width * .50, s.height * .91, s.width * .25, s.height * .67)
      ..close();
    canvas.drawPath(shield, p);
    final inner = Paint()
      ..color = Colors.white.withOpacity(.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .045;
    canvas.drawPath(
      Path()
        ..moveTo(s.width * .25, s.height * .29)
        ..lineTo(s.width * .50, s.height * .18)
        ..lineTo(s.width * .75, s.height * .29),
      inner,
    );
    final star = Paint()..color = accent;
    final starPath = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? s.width * .105 : s.width * .045;
      final pt = Offset(
          s.width * .50 + math.cos(a) * r, s.height * .47 + math.sin(a) * r);
      if (i == 0) {
        starPath.moveTo(pt.dx, pt.dy);
      } else {
        starPath.lineTo(pt.dx, pt.dy);
      }
    }
    starPath.close();
    canvas.drawPath(starPath, star);
  }

  void _traffic(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          s.width * .30, s.height * .07, s.width * .40, s.height * .86),
      Radius.circular(s.width * .12),
    );
    canvas.drawRRect(body, Paint()..color = Colors.black.withOpacity(.38));
    canvas.drawRRect(body, _line(s.width * .055));
    const lights = [Color(0xFFFF4D5A), Color(0xFFFFC72C), Color(0xFF43E07A)];
    for (var i = 0; i < 3; i++) {
      final center = Offset(s.width * .50, s.height * (.25 + i * .25));
      canvas.drawCircle(
          center, s.width * .095, Paint()..color = lights[i].withOpacity(.18));
      canvas.drawCircle(center, s.width * .072, Paint()..color = lights[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _RoadAlertPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.color != color ||
      oldDelegate.accent != accent;
}
