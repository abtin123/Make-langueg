
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum BranchType { entrance, mainExit, secondaryExit }

@immutable
class ArrowData {
  const ArrowData({
    this.enabled = true,
    this.length = 30,
    this.width = 18,
    this.thickness = 1,
    this.position = .78,
    this.color,
  });
  final bool enabled;
  final double length;
  final double width;
  final double thickness;
  final double position;
  final Color? color;
}

@immutable
class BranchData {
  const BranchData({
    required this.angleDeg,
    required this.type,
    this.length = 190,
    this.curve = 0,
    this.color,
    this.opacity = 1,
    this.strokeWidth,
    this.active = false,
    this.showArrow = true,
    this.arrow,
    this.controlPoint1,
    this.controlPoint2,
    this.customPath,
    this.id,
  });
  final double angleDeg;
  final BranchType type;
  final double length;
  final double curve;
  final Color? color;
  final double opacity;
  final double? strokeWidth;
  final bool active;
  final bool showArrow;
  final ArrowData? arrow;
  final Offset? controlPoint1;
  final Offset? controlPoint2;
  final String? customPath;
  final String? id;
}

@immutable
class RoundaboutStyle {
  const RoundaboutStyle({
    this.roundaboutColor = Colors.white,
    this.entranceColor = Colors.white,
    this.mainExitColor = const Color(0xFF35D6D1),
    this.secondaryExitColor = Colors.white,
    this.laneMarkColor = Colors.white,
    this.glowColor = const Color(0xFF35D6D1),
    this.roundaboutOpacity = 1,
    this.entranceOpacity = .65,
    this.mainExitOpacity = 1,
    this.secondaryExitOpacity = .25,
    this.laneMarkOpacity = .62,
    this.glowOpacity = .18,
    this.roadWidth = 22,
    this.ringWidth = 22,
    this.laneMarkWidth = 2,
    this.glowWidth = 7,
    this.arrowLength = 30,
    this.arrowWidth = 18,
    this.arrowThickness = 1,
    this.arrowPosition = .78,
    this.glowEnabled = false,
    this.showLaneMarks = true,
  });

  final Color roundaboutColor;
  final Color entranceColor;
  final Color mainExitColor;
  final Color secondaryExitColor;
  final Color laneMarkColor;
  final Color glowColor;
  final double roundaboutOpacity;
  final double entranceOpacity;
  final double mainExitOpacity;
  final double secondaryExitOpacity;
  final double laneMarkOpacity;
  final double glowOpacity;
  final double roadWidth;
  final double ringWidth;
  final double laneMarkWidth;
  final double glowWidth;
  final double arrowLength;
  final double arrowWidth;
  final double arrowThickness;
  final double arrowPosition;
  final bool glowEnabled;
  final bool showLaneMarks;

  Color colorFor(BranchData b) {
    if (b.color != null) return b.color!;
    return switch (b.type) {
      BranchType.entrance => entranceColor,
      BranchType.mainExit => mainExitColor,
      BranchType.secondaryExit => secondaryExitColor,
    };
  }

  double opacityFor(BranchData b) {
    final base = switch (b.type) {
      BranchType.entrance => entranceOpacity,
      BranchType.mainExit => mainExitOpacity,
      BranchType.secondaryExit => secondaryExitOpacity,
    };
    return (base * b.opacity).clamp(0.0, 1.0);
  }
}

@immutable
class RoundaboutData {
  const RoundaboutData({
    this.canvas = const Size(512, 512),
    this.center = const Offset(256, 256),
    this.radius = 92,
    this.branches = const [],
    this.activeExit,
    this.style = const RoundaboutStyle(),
    this.roundaboutId = 'roundabout',
  });
  final Size canvas;
  final Offset center;
  final double radius;
  final List<BranchData> branches;
  final int? activeExit;
  final RoundaboutStyle style;
  final String roundaboutId;
}

class RoundaboutGeometry {
  const RoundaboutGeometry(this.data);
  final RoundaboutData data;

  Offset direction(double degrees) {
    final a = degrees * math.pi / 180;
    return Offset(math.cos(a), math.sin(a));
  }

  Path branchPath(BranchData b) {
    if (b.customPath != null) {
      final parsed = _parsePath(b.customPath!);
      if (parsed != null) return parsed;
    }
    final dir = direction(b.angleDeg);
    final tangent = Offset(-dir.dy, dir.dx);
    final start = data.center + dir * (data.radius - data.style.roadWidth * .18);
    final end = data.center + dir * (data.radius + b.length);
    final c1 = b.controlPoint1 ??
        start + dir * (b.length * .30) + tangent * b.curve;
    final c2 = b.controlPoint2 ??
        end - dir * (b.length * .30) + tangent * b.curve;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  }

  TangentSample sample(BranchData b, double t) {
    final metrics = branchPath(b).computeMetrics().toList();
    if (metrics.isEmpty) return TangentSample(data.center, direction(b.angleDeg));
    final m = metrics.first;
    final tan = m.getTangentForOffset(m.length * t.clamp(0, 1));
    return tan == null
        ? TangentSample(data.center, direction(b.angleDeg))
        : TangentSample(tan.position, _unit(tan.vector));
  }

  Path? _parsePath(String value) {
    final tokens = RegExp(r'[MLQCZ]|-?\d+(?:\.\d+)?')
        .allMatches(value.toUpperCase())
        .map((m) => m.group(0)!)
        .toList();
    if (tokens.isEmpty) return null;
    final p = Path();
    var i = 0;
    String? cmd;
    double n() => double.parse(tokens[i++]);
    try {
      while (i < tokens.length) {
        if (RegExp(r'^[MLQCZ]$').hasMatch(tokens[i])) cmd = tokens[i++];
        switch (cmd) {
          case 'M': p.moveTo(n(), n()); cmd = 'L'; break;
          case 'L': p.lineTo(n(), n()); break;
          case 'Q': p.quadraticBezierTo(n(), n(), n(), n()); break;
          case 'C': p.cubicTo(n(), n(), n(), n(), n(), n()); break;
          case 'Z': p.close(); cmd = null; break;
          default: return null;
        }
      }
      return p;
    } catch (_) {
      return null;
    }
  }
}

class TangentSample {
  const TangentSample(this.position, this.direction);
  final Offset position;
  final Offset direction;
}

int _branchLayer(BranchType type) => switch (type) {
      BranchType.secondaryExit => 0,
      BranchType.entrance => 1,
      BranchType.mainExit => 2,
    };

Offset _unit(Offset v) {
  final d = v.distance;
  return d == 0 ? const Offset(1, 0) : Offset(v.dx / d, v.dy / d);
}

class RoundaboutPainter extends CustomPainter {
  const RoundaboutPainter(this.data);
  final RoundaboutData data;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / data.canvas.width;
    final sy = size.height / data.canvas.height;
    canvas.save();
    canvas.scale(sx, sy);
    final s = data.style;
    final g = RoundaboutGeometry(data);

    // Secondary exits first, entrance branches next, and the actual route
    // exit last. This guarantees the highlighted/main exit is visibly on top
    // instead of disappearing underneath another branch at a crossing.
    final branches = [...data.branches]
      ..sort((a, b) => _branchLayer(a.type).compareTo(_branchLayer(b.type)));
    for (var i = 0; i < branches.length; i++) {
      final branch = branches[i];
      final opacity = s.opacityFor(branch);
      final color = s.colorFor(branch).withOpacity(opacity);
      final path = g.branchPath(branch);
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = branch.strokeWidth ?? s.roadWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      if (s.showLaneMarks) {
        _dashedPath(canvas, path, Paint()
          ..color = s.laneMarkColor.withOpacity(opacity * s.laneMarkOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.laneMarkWidth);
      }

      final a = branch.arrow ??
          ArrowData(
            enabled: branch.showArrow,
            length: s.arrowLength,
            width: s.arrowWidth,
            thickness: s.arrowThickness,
            position: s.arrowPosition,
            color: color,
          );
      if (branch.showArrow && a.enabled) _arrow(canvas, g.sample(branch, a.position), a, a.color ?? color);
    }

    // حلقهٔ میدان عمداً در لایهٔ بالاتر از همهٔ ورودی‌ها/خروجی‌ها رسم می‌شود.
    if (s.glowEnabled && s.glowOpacity > 0) {
      canvas.drawCircle(
        data.center,
        data.radius,
        Paint()
          ..color = s.glowColor.withOpacity(s.glowOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.ringWidth + s.glowWidth
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.glowWidth),
      );
    }

    canvas.drawCircle(
      data.center,
      data.radius,
      Paint()
        ..color = s.roundaboutColor.withOpacity(s.roundaboutOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.ringWidth
        ..strokeCap = StrokeCap.round,
    );

    final border = Paint()
      ..color = s.roundaboutColor.withOpacity(s.roundaboutOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(data.center, data.radius + s.ringWidth / 2, border);
    canvas.drawCircle(data.center, math.max(0, data.radius - s.ringWidth / 2), border);

    if (s.showLaneMarks) {
      _dashedCircle(canvas, data.center, data.radius, Paint()
        ..color = s.laneMarkColor.withOpacity(s.laneMarkOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.laneMarkWidth
        ..strokeCap = StrokeCap.round);
    }

    // میانِ میدان دیگر یک دیسکِ رنگیِ توپر نیست — کاملاً خالی می‌ماند (نقشه
    // از زیرش دیده می‌شود) و فقط شماره‌ی خروجیِ انتخاب‌شده وسطِ همان فضای
    // خالی نوشته می‌شود.
    if (data.activeExit != null) {
      final innerRadius = math.max(0, data.radius - s.ringWidth * .62);
      final fontSize = innerRadius * 1.05;
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${data.activeExit}',
          style: TextStyle(
            color: s.mainExitColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        data.center -
            Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
    canvas.restore();
  }

  void _arrow(Canvas c, TangentSample sample, ArrowData a, Color color) {
    final d = _unit(sample.direction);
    final n = Offset(-d.dy, d.dx);
    final tip = sample.position + d * (a.length / 2);
    final base = sample.position - d * (a.length / 2);
    final left = base + n * (a.width / 2);
    final right = base - n * (a.width / 2);
    final p = Path()
      ..moveTo(base.dx, base.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    c.drawPath(p, Paint()..color = color..style = PaintingStyle.fill);
    if (a.thickness > 0) {
      c.drawPath(p, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = a.thickness.clamp(.5, 6)
        ..strokeJoin = StrokeJoin.round);
    }
  }

  void _dashedPath(Canvas c, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      const dash = 15.0, gap = 12.0;
      for (var d = 0.0; d < m.length; d += dash + gap) {
        c.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  void _dashedCircle(Canvas c, Offset center, double r, Paint paint) {
    const dash = .16, gap = .13;
    for (var a = 0.0; a < math.pi * 2; a += dash + gap) {
      final p = Path()
        ..moveTo(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r)
        ..lineTo(center.dx + math.cos(math.min(a + dash, math.pi * 2)) * r,
            center.dy + math.sin(math.min(a + dash, math.pi * 2)) * r);
      c.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RoundaboutPainter oldDelegate) => oldDelegate.data != data;
}

class RoundaboutSvgBuilder {
  const RoundaboutSvgBuilder();

  String build(RoundaboutData data) {
    final g = RoundaboutGeometry(data);
    final s = data.style;
    final out = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${data.canvas.width} ${data.canvas.height}">')
      ..writeln('<g id="${_id(data.roundaboutId)}">');

    // Keep the same layer order as the CustomPainter: the active/main exit
    // is serialized last so SVG rendering also keeps it visually dominant.
    final branches = [...data.branches]
      ..sort((a, b) => _branchLayer(a.type).compareTo(_branchLayer(b.type)));
    for (var i = 0; i < branches.length; i++) {
      final b = branches[i];
      final id = _id(b.id ?? '${b.type.name}_$i');
      final path = b.customPath?.trim().isNotEmpty == true ? b.customPath! : _cubicSvg(b, data);
      final color = s.colorFor(b);
      final opacity = s.opacityFor(b);
      out.writeln('<g id="$id" data-type="${b.type.name}" data-active="${b.active}">');
      out.writeln('<path id="${id}_path" d="$path" fill="none" stroke="${_hex(color)}" stroke-opacity="${_n(opacity)}" stroke-width="${_n(b.strokeWidth ?? s.roadWidth)}" stroke-linecap="round" stroke-linejoin="round"/>');
      if (s.showLaneMarks) {
        out.writeln('<path id="${id}_laneMarks" d="$path" fill="none" stroke="${_hex(s.laneMarkColor)}" stroke-opacity="${_n(opacity * s.laneMarkOpacity)}" stroke-width="${_n(s.laneMarkWidth)}" stroke-dasharray="15 12" stroke-linecap="round"/>');
      }
      final a = b.arrow ?? ArrowData(enabled: b.showArrow, length: s.arrowLength, width: s.arrowWidth, thickness: s.arrowThickness, position: s.arrowPosition, color: color);
      if (b.showArrow && a.enabled) {
        final sample = g.sample(b, a.position);
        final d = _unit(sample.direction), n = Offset(-d.dy, d.dx);
        final tip = sample.position + d * (a.length / 2);
        final base = sample.position - d * (a.length / 2);
        final left = base + n * (a.width / 2), right = base - n * (a.width / 2);
        out.writeln('<path id="${id}_arrow" d="M ${_n(base.dx)} ${_n(base.dy)} L ${_n(left.dx)} ${_n(left.dy)} L ${_n(tip.dx)} ${_n(tip.dy)} L ${_n(right.dx)} ${_n(right.dy)} Z" fill="${_hex(a.color ?? color)}" stroke="${_hex(a.color ?? color)}" stroke-width="${_n(a.thickness.clamp(.5, 6))}" stroke-linejoin="round"/>');
      }
      out.writeln('</g>');
    }

    if (s.glowEnabled && s.glowOpacity > 0) {
      out.writeln('<circle id="roundaboutGlow" cx="${_n(data.center.dx)}" cy="${_n(data.center.dy)}" r="${_n(data.radius)}" fill="none" stroke="${_hex(s.glowColor)}" stroke-opacity="${_n(s.glowOpacity)}" stroke-width="${_n(s.ringWidth + s.glowWidth)}"/>');
    }
    out.writeln('<circle id="roundabout" cx="${_n(data.center.dx)}" cy="${_n(data.center.dy)}" r="${_n(data.radius)}" fill="none" stroke="${_hex(s.roundaboutColor)}" stroke-opacity="${_n(s.roundaboutOpacity)}" stroke-width="${_n(s.ringWidth)}"/>');
    out.writeln('<circle id="outerBorder" cx="${_n(data.center.dx)}" cy="${_n(data.center.dy)}" r="${_n(data.radius + s.ringWidth / 2)}" fill="none" stroke="${_hex(s.roundaboutColor)}" stroke-opacity="${_n(s.roundaboutOpacity)}" stroke-width="2"/>');
    out.writeln('<circle id="innerBorder" cx="${_n(data.center.dx)}" cy="${_n(data.center.dy)}" r="${_n(math.max(0, data.radius - s.ringWidth / 2))}" fill="none" stroke="${_hex(s.roundaboutColor)}" stroke-opacity="${_n(s.roundaboutOpacity)}" stroke-width="2"/>');

    if (s.showLaneMarks) {
      out.writeln('<circle id="laneMarks" cx="${_n(data.center.dx)}" cy="${_n(data.center.dy)}" r="${_n(data.radius)}" fill="none" stroke="${_hex(s.laneMarkColor)}" stroke-opacity="${_n(s.laneMarkOpacity)}" stroke-width="${_n(s.laneMarkWidth)}" stroke-dasharray="18 13"/>');
    }

    // فضای داخلی عمداً خالی/شفاف است و فقط شمارهٔ خروجیِ فعال داخل همان
    // سوراخ قرار می‌گیرد. اندازهٔ عدد از شعاعِ داخلی محاسبه می‌شود تا از حلقه
    // عبور نکند.
    if (data.activeExit != null) {
      final innerRadius = math.max(0, data.radius - s.ringWidth / 2 - 3);
      final fontSize = math.max(10, innerRadius * .82);
      out.writeln('<text id="centerExitNumber" x="${_n(data.center.dx)}" y="${_n(data.center.dy)}" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-weight="800" font-size="${_n(fontSize)}" fill="${_hex(s.mainExitColor)}">${data.activeExit}</text>');
    }
    return '${out.toString()}</g></svg>';
  }

  String _cubicSvg(BranchData b, RoundaboutData d) {
    final a = b.angleDeg * math.pi / 180;
    final dir = Offset(math.cos(a), math.sin(a));
    final tan = Offset(-dir.dy, dir.dx);
    final start = d.center + dir * (d.radius - d.style.roadWidth * .18);
    final end = d.center + dir * (d.radius + b.length);
    final c1 = b.controlPoint1 ?? start + dir * (b.length * .30) + tan * b.curve;
    final c2 = b.controlPoint2 ?? end - dir * (b.length * .30) + tan * b.curve;
    return 'M ${_n(start.dx)} ${_n(start.dy)} C ${_n(c1.dx)} ${_n(c1.dy)}, ${_n(c2.dx)} ${_n(c2.dy)}, ${_n(end.dx)} ${_n(end.dy)}';
  }

  String _hex(Color c) => '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  String _n(double n) => n.toStringAsFixed(2);
  String _id(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

class RoundaboutManeuverIcon extends StatelessWidget {
  const RoundaboutManeuverIcon({
    super.key,
    required this.color,
    this.exit,
    this.exitCount,
    this.angleDegrees,
    this.branchAngles = const [],
    this.entranceAngles = const [],
    this.exitAngles = const [],
    this.activeExitAngle,
    this.drivingSide = 'right',
    this.thickness = .72,
    this.sizeFactor = .88,
    this.style,
  });

  final Color color;
  final int? exit;
  final int? exitCount;
  final double? angleDegrees;
  final List<double> branchAngles;
  final List<double> entranceAngles;
  final List<double> exitAngles;
  final double? activeExitAngle;
  final String drivingSide;
  final double thickness;
  final double sizeFactor;
  final RoundaboutStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) {
          final side = math.min(c.maxWidth.isFinite ? c.maxWidth : 92,
              c.maxHeight.isFinite ? c.maxHeight : 92);
          final data = _makeData(side.toDouble());
          final svg = const RoundaboutSvgBuilder().build(data);
          return Center(
            child: SvgPicture.string(
              svg,
              width: side * sizeFactor,
              height: side * sizeFactor,
              fit: BoxFit.contain,
            ),
          );
        },
      );

  RoundaboutData _makeData(double side) {
    // Offline routing supplies the real physical arm bearings from map.sqlite.
    // Never invent four branches when that data is available.
    final suppliedAngles = <double>[];
    for (final raw in branchAngles) {
      // Routing stores geographic bearings (0=north, clockwise); the icon
      // canvas uses mathematical screen angles (0=right, 90=down).
      final normalized = ((raw - 90) % 360 + 360) % 360;
      if (!suppliedAngles.any((a) {
        var d = (a - normalized).abs();
        if (d > 180) d = 360 - d;
        return d <= 7.5;
      })) suppliedAngles.add(normalized);
    }
    // Never invent a four-arm roundabout. Exact bearings are expected from
    // the active routing provider; if the provider cannot supply them, keep
    // the ring only instead of drawing fabricated exits.
    final count = suppliedAngles.isNotEmpty
        ? suppliedAngles.length
        : (exitCount ?? 0).clamp(0, 32).toInt();
    final clockwise = angleDegrees != null
        ? angleDegrees! >= 0
        : drivingSide.toLowerCase() != 'left';

    final angles = suppliedAngles.isNotEmpty
        ? suppliedAngles
        : const <double>[];

    double circularDistance(double a, double b) {
      var d = (a - b).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    bool matchesAny(double angle, List<double> targets) => targets.any(
          (target) => circularDistance(
                angle,
                ((target - 90) % 360 + 360) % 360,
              ) <= 12,
        );

    final activeAngle = activeExitAngle == null
        ? null
        : ((activeExitAngle - 90) % 360 + 360) % 360;
    final active = activeAngle == null
        ? (exit == null ? null : exit!.clamp(1, angles.length).toInt())
        : null;
    final branches = <BranchData>[];
    for (var i = 0; i < angles.length; i++) {
      final angle = angles[i];
      final isMain = activeAngle != null
          ? circularDistance(angle, activeAngle) <= 12
          : active == i + 1;
      final isEntrance = matchesAny(angle, entranceAngles);
      final isExit = exitAngles.isEmpty || matchesAny(angle, exitAngles);
      final type = isMain
          ? BranchType.mainExit
          : isEntrance
              ? BranchType.entrance
              : isExit
                  ? BranchType.secondaryExit
                  : BranchType.entrance;
      final fraction = i / math.max(1, angles.length);
      branches.add(BranchData(
        angleDeg: angle,
        type: type,
        length: side * .27,
        curve: math.sin(fraction * math.pi) * side * .035,
        id: isMain
            ? 'mainExit'
            : isEntrance
                ? 'entrance_$i'
                : 'secondaryExit_$i',
        active: isMain,
      ));
    }
    final width = math.max(3.5, side * .062) * (.72 + thickness * .18);
    final baseStyle = style;
    return RoundaboutData(
      canvas: Size.square(side),
      center: Offset(side / 2, side / 2),
      radius: side * .285,
      branches: branches,
      activeExit: active,
      style: baseStyle ?? RoundaboutStyle(
        roundaboutColor: Colors.white,
        entranceColor: Colors.white,
        mainExitColor: color,
        secondaryExitColor: Colors.white,
        laneMarkColor: Colors.white,
        roundaboutOpacity: 1,
        entranceOpacity: .65,
        mainExitOpacity: 1,
        secondaryExitOpacity: .25,
        laneMarkOpacity: .42,
        roadWidth: width,
        ringWidth: width,
        laneMarkWidth: math.max(1, side * .014),
        arrowLength: math.max(10, side * .11),
        arrowWidth: math.max(7, side * .07),
        arrowThickness: math.max(.6, thickness * 1.4),
        arrowPosition: .72,
      ),
    );
  }
}

/// Six-branch sample requested by the design contract: 2 entrances,
/// 3 secondary exits and 1 active/main exit.
RoundaboutData sixBranchRoundaboutExample(Color mainColor) => RoundaboutData(
  branches: const [
    BranchData(angleDeg: 90, type: BranchType.entrance, color: Colors.white, opacity: .65, id: 'entrance_0'),
    BranchData(angleDeg: 210, type: BranchType.entrance, color: Colors.white, opacity: .65, id: 'entrance_1'),
    BranchData(angleDeg: 30, type: BranchType.secondaryExit, color: Colors.white, opacity: .25, id: 'secondaryExit_0'),
    BranchData(angleDeg: -30, type: BranchType.secondaryExit, color: Colors.white, opacity: .25, id: 'secondaryExit_1'),
    BranchData(angleDeg: -90, type: BranchType.mainExit, color: Color(0xFF35D6D1), opacity: 1, active: true, id: 'mainExit'),
    BranchData(angleDeg: 150, type: BranchType.secondaryExit, color: Colors.white, opacity: .25, id: 'secondaryExit_2'),
  ],
  activeExit: 4,
  style: RoundaboutStyle(mainExitColor: mainColor),
);
