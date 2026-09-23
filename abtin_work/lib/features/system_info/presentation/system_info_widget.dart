import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../settings/domain/appearance_settings.dart';

class SystemInfoWidget extends StatefulWidget {
  const SystemInfoWidget({
    super.key,
    this.scale = 1,
    this.background = const Color(0x8C000000),
    this.textColor = Colors.white,
    this.contentAlign = 0,
    this.batteryOrientation = BatteryIconOrientation.horizontal,
    this.batterySizePercent = 100.0,
    this.batteryColor = Colors.transparent,
  });

  final double scale;
  final Color background;
  final Color textColor;
  final double contentAlign;

  /// جهتِ نمایشِ آیکونِ باتری.
  final BatteryIconOrientation batteryOrientation;

  /// اندازهٔ اختصاصیِ آیکونِ باتری، به‌صورتِ درصد (۱۰۰ = اندازهٔ اصلی).
  final double batterySizePercent;

  /// رنگِ اختصاصیِ آیکونِ باتری. transparent یعنی از [textColor] استفاده
  /// شود (رفتارِ پیش‌فرضِ قبلی، بدون تغییر ظاهر).
  final Color batteryColor;

  @override
  State<SystemInfoWidget> createState() => _SystemInfoWidgetState();
}

class _SystemInfoWidgetState extends State<SystemInfoWidget> {
  static const _channel = MethodChannel('ir.abtin.abtin_maps/device_battery');
  Timer? _timer;
  int _battery = -1;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _readBattery();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _readBattery();
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _readBattery() async {
    try {
      final value = await _channel.invokeMethod<int>('batteryLevel');
      if (mounted && value != null) setState(() => _battery = value);
    } catch (_) {
      // اگر دستگاه/پلتفرم battery channel نداشت، ساعت همچنان نمایش داده شود.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Transform.scale(
      scale: widget.scale,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: widget.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BatteryIcon(
              level: _battery,
              color: widget.batteryColor.alpha == 0
                  ? widget.textColor
                  : widget.batteryColor,
              orientation: widget.batteryOrientation,
              sizePercent: widget.batterySizePercent,
            ),
            const SizedBox(width: 7),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: widget.contentAlign >= 50
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  '$hh:$mm',
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _battery >= 0 ? '$_battery%' : '—',
                  style: TextStyle(
                    color: widget.textColor.withOpacity(.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({
    required this.level,
    required this.color,
    this.orientation = BatteryIconOrientation.horizontal,
    this.sizePercent = 100.0,
  });
  final int level;
  final Color color;
  final BatteryIconOrientation orientation;
  final double sizePercent;

  @override
  Widget build(BuildContext context) {
    final fraction = level < 0 ? .0 : (level / 100).clamp(0.0, 1.0);
    final fillColor =
        level >= 0 && level <= 20 ? const Color(0xFFFF5A5F) : color;
    final scale = (sizePercent / 100.0).clamp(0.5, 2.0);
    final vertical = orientation == BatteryIconOrientation.vertical;
    // پینتر همیشه با هندسهٔ افقی (باتری «خوابیده») رسم می‌شود؛ برای حالتِ
    // عمودی، فقط جعبه ۹۰ درجه می‌چرخد تا ترمینالِ باتری رو به بالا بیاید.
    final box = SizedBox(
      width: 29 * scale,
      height: 18 * scale,
      child: CustomPaint(
        painter: _BatteryPainter(fraction: fraction, color: fillColor),
      ),
    );
    if (!vertical) return box;
    return SizedBox(
      width: 18 * scale,
      height: 29 * scale,
      child: RotatedBox(quarterTurns: 3, child: box),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 5, size.height - 2),
      const Radius.circular(4),
    );
    canvas.drawRRect(body, stroke);
    final terminal = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 4, size.height * .34, 3, size.height * .32),
        const Radius.circular(1.5),
      ),
      terminal,
    );
    if (fraction > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            3,
            3,
            (size.width - 9) * fraction,
            size.height - 6,
          ),
          const Radius.circular(2.5),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}
