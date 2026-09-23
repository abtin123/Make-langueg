import 'package:flutter/material.dart';

/// track مشترک Sliderهای آبتین مپس. بخش فعال با گرادیان کشیده می‌شود و بخش
/// باقی‌مانده خنثی است؛ جهت RTL نیز مانند Slider استاندارد رعایت می‌شود.
class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const GradientSliderTrackShape({required this.gradient});

  final Gradient gradient;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required TextDirection textDirection,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final fullTrack = RRect.fromRectAndRadius(trackRect, radius);
    final inactive = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white24;
    canvas.drawRRect(fullTrack, inactive);

    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(
            trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom)
        : Rect.fromLTRB(
            thumbCenter.dx, trackRect.top, trackRect.right, trackRect.bottom);
    if (activeRect.width <= 0) return;

    canvas.save();
    canvas.clipRRect(fullTrack);
    canvas.drawRect(
      activeRect,
      Paint()..shader = gradient.createShader(trackRect),
    );
    canvas.restore();
  }
}
