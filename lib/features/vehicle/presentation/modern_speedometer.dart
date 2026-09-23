import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Visual speedometer. The navigation pipeline is the single source of truth
/// and already rate-limits speed at the presentation boundary. This widget is
/// deliberately passive: adding a second animation here would double the lag,
/// especially while braking.
class ModernSpeedometer extends StatefulWidget {
  final double speedKmh;
  final double maxSpeed;

  const ModernSpeedometer({
    super.key,
    required this.speedKmh,
    this.maxSpeed = 240.0,
  });

  @override
  State<ModernSpeedometer> createState() => _ModernSpeedometerState();
}

class _ModernSpeedometerState extends State<ModernSpeedometer> {
  double _displayedSpeed = 0;

  @override
  void initState() {
    super.initState();
    _displayedSpeed = _sanitize(widget.speedKmh);
  }

  @override
  void didUpdateWidget(covariant ModernSpeedometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مقدار قبلی عمداً حفظ می‌شود تا TweenAnimationBuilder تغییر سرعت را
    // نرم کند و در ترمزهای سریع، عقربه و عدد ناگهان نپرند.
  }

  double _sanitize(double speed) {
    if (!speed.isFinite) return 0;
    return speed.clamp(0.0, widget.maxSpeed).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 100.0;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 100.0;
        final size = math.min(maxW, maxH) > 0 ? math.min(maxW, maxH) : 100.0;
        final scale = size / 100.0;
        final targetSpeed = _sanitize(widget.speedKmh);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: _displayedSpeed, end: targetSpeed),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (mounted) _displayedSpeed = targetSpeed;
          },
          builder: (context, animatedSpeed, child) => SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/images/speedometer.webp',
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                ),
                CustomPaint(
                  size: Size(size, size),
                  painter: _SpeedometerPainter(
                      speed: animatedSpeed, maxSpeed: widget.maxSpeed),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      animatedSpeed.round().toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 8 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  _SpeedometerPainter({required this.speed, required this.maxSpeed});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final speedPercent = (speed / maxSpeed).clamp(0.0, 1.0);

    final speedPaint = Paint()
      ..shader = const SweepGradient(
        colors: [AppColors.speedLow, AppColors.speedMid, AppColors.speedHigh],
        stops: [0.0, 0.5, 1.0],
        startAngle: math.pi * 0.75,
        endAngle: math.pi * 2.25,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 10 * scale),
      math.pi * 0.75,
      math.pi * 1.5 * speedPercent,
      false,
      speedPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) =>
      oldDelegate.speed != speed || oldDelegate.maxSpeed != maxSpeed;
}
