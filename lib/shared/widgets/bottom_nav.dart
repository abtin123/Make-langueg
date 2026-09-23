import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/voice_settings/presentation/tts_providers.dart';
import '../../core/localization/app_localizations.dart';
import '../../features/search/presentation/search_providers.dart';
import '../../features/settings/presentation/appearance_settings_providers.dart';

enum NavKey { settings, voice, home, saved, routes, search }

/// Pixel-locked counterpart of preview.html's bottom navigation.
///
/// The HTML reference is ONE continuous floating bar (1214x150, design
/// coordinates) with only its two top corners rounded (r=48) and a single
/// perforated circular hole (r=122, centered on the top edge) that slides
/// under whichever slot is active. The active slot itself grows from a flat
/// 120px circle sitting at bottom:15 into a 190px circle that rises to
/// bottom:90, gets a 5px light border and a purple radial-gradient fill, and
/// its icon grows from 64px (dim) to 78px (white). Every slot — settings,
/// voice, home, saved, search — uses exactly the same elevate animation;
/// none of them is special-cased in the HTML, so none is special-cased here
/// either. All positions/sizes below are taken verbatim from the HTML's
/// design coordinates and only ever multiplied by `scale`.
class BottomNav extends ConsumerStatefulWidget {
  final NavKey currentPage;
  final bool isHomePage;

  const BottomNav({super.key, required this.currentPage, this.isHomePage = false});

  @override
  ConsumerState<BottomNav> createState() => _BottomNavState();
}

/// Design-space (1214-wide) center-x of each slot, exactly as in the HTML's
/// `data-x` attributes.
const Map<NavKey, double> _slotX = {
  NavKey.settings: 121,
  NavKey.voice: 364,
  NavKey.home: 607,
  NavKey.saved: 850,
  NavKey.search: 1093,
};

const List<NavKey> _slotOrder = [
  NavKey.settings,
  NavKey.voice,
  NavKey.home,
  NavKey.saved,
  NavKey.search,
];

// HTML: `.slot { ... transition: width .42s cubic-bezier(.5,-.2,.3,1.15), ... }`
const _elevateCurve = Cubic(0.5, -0.2, 0.3, 1.15);
const _elevateDuration = Duration(milliseconds: 420);

class _BottomNavState extends ConsumerState<BottomNav> with TickerProviderStateMixin {
  late final Map<NavKey, AnimationController> _ctrls = {
    for (final k in _slotOrder) k: AnimationController(vsync: this, duration: _elevateDuration),
  };

  Map<NavKey, bool> _computeActive() {
    final searchActive = ref.read(searchActiveProvider);
    return <NavKey, bool>{
      NavKey.settings: widget.currentPage == NavKey.settings,
      // Voice enabled/muted is a functional state, not menu selection.
      // Only the voice-settings page owns the nav item's active animation.
      NavKey.voice: widget.currentPage == NavKey.voice,
      NavKey.home: widget.currentPage == NavKey.home && !searchActive,
      NavKey.saved: widget.currentPage == NavKey.saved,
      NavKey.search: searchActive || widget.currentPage == NavKey.search,
    };
  }

  @override
  void initState() {
    super.initState();
    // Jump straight to the right slot on first mount — no entry animation,
    // matching the HTML where the initial active slot starts elevated.
    _computeActive().forEach((k, isActive) {
      if (isActive) _ctrls[k]!.value = 1.0;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTarget(NavKey key, bool active) {
    final c = _ctrls[key]!;
    final target = active ? 1.0 : 0.0;
    final alreadyGoing = (target == 1.0 && c.status == AnimationStatus.forward) ||
        (target == 0.0 && c.status == AnimationStatus.reverse);
    if (c.value != target && !alreadyGoing) {
      c.animateTo(target, curve: _elevateCurve, duration: _elevateDuration);
    }
  }

  void _toggleVoice() {
    final notifier = ref.read(ttEnabledProvider.notifier);
    final next = !ref.read(ttEnabledProvider);
    notifier.set(next);
    if (!next) ref.read(ttsServiceProvider).stop();
  }

  void _onTap(NavKey key) {
    // Search is a Home-only overlay. Any navigation away from Home must close
    // its global state before the destination page is built.
    if (key != NavKey.search && ref.read(searchActiveProvider)) {
      ref.read(searchActiveProvider.notifier).state = false;
    }
    if (key == NavKey.voice) {
      _toggleVoice();
      return;
    }
    if (key == NavKey.search) {
      // Search belongs to Home because the result overlay is rendered by
      // HomeScreen. From any other page, return Home first and then open it;
      // never leave a global search state active on a settings/favorites page.
      ref.read(searchActiveProvider.notifier).state = true;
      if (widget.currentPage != NavKey.home) {
        context.go('/');
      }
      return;
    }
    switch (key) {
      case NavKey.home:
        if (ref.read(searchActiveProvider)) {
          ref.read(searchActiveProvider.notifier).state = false;
        } else {
          context.go('/');
        }
      case NavKey.saved:
        context.push('/saved-places');
      case NavKey.routes:
        context.go('/routes');
      case NavKey.settings:
        context.push('/settings');
      case NavKey.voice:
      case NavKey.search:
        break;
    }
  }

  void _onLongPress(NavKey key) {
    if (key == NavKey.voice) context.push('/voice-settings');
  }

  String _label(BuildContext context, NavKey key) => switch (key) {
        NavKey.settings => AppStrings.get(context, ref, 'settings'),
        NavKey.voice => AppStrings.get(context, ref, 'voice'),
        NavKey.home => AppStrings.get(context, ref, 'home'),
        NavKey.saved => AppStrings.get(context, ref, 'favorites'),
        NavKey.routes => AppStrings.get(context, ref, 'routes'),
        NavKey.search => AppStrings.get(context, ref, 'search'),
      };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = width / 1214.0;
    final voiceEnabled = ref.watch(ttEnabledProvider);
    final searchActive = ref.watch(searchActiveProvider);
    final appearance = ref.watch(appearanceSettingsProvider);

    final active = <NavKey, bool>{
      NavKey.settings: widget.currentPage == NavKey.settings,
      NavKey.voice: widget.currentPage == NavKey.voice,
      NavKey.home: widget.currentPage == NavKey.home && !searchActive,
      NavKey.saved: widget.currentPage == NavKey.saved,
      NavKey.search: searchActive || widget.currentPage == NavKey.search,
    };
    // (kept in sync with _computeActive(), which initState() uses before the
    // first ref.watch-driven build exists.)
    for (final k in _slotOrder) {
      _syncTarget(k, active[k] ?? false);
    }

    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: Listenable.merge(_ctrls.values.toList()),
        builder: (context, _) {
          final ts = {for (final k in _slotOrder) k: _ctrls[k]!.value};
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // HTML: svg.bottombar-svg — 1214x150, anchored bottom-left.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 150 * scale,
                child: CustomPaint(
                  painter: _BarPainter(
                    scale: scale,
                    slotT: ts,
                    backgroundColor: appearance.bottomNavBackgroundColor,
                    borderColor: appearance.bottomNavBorderColor,
                    glowColor: appearance.bottomNavGlowColor,
                    opacity: appearance.bottomNavOpacity,
                  ),
                ),
              ),
              for (final k in _slotOrder)
                _slot(
                  key: k,
                  label: _label(context, k),
                  t: ts[k]!,
                  scale: scale,
                  icon: _iconFor(k, voiceEnabled: voiceEnabled),
                  appearance: appearance,
                  onTap: () => _onTap(k),
                  onLongPress: k == NavKey.voice ? () => _onLongPress(k) : null,
                ),
            ],
          );
        },
      ),
    );
  }

  String _iconFor(NavKey k, {required bool voiceEnabled}) => switch (k) {
        NavKey.settings => _settingsSvg,
        NavKey.voice => voiceEnabled ? _voiceSvg : _voiceMutedSvg,
        NavKey.home => _homeSvg,
        NavKey.saved => _starSvg,
        NavKey.search => _searchSvg,
        NavKey.routes => _homeSvg,
      };

  Widget _slot({
    required NavKey key,
    required String label,
    required double t,
    required double scale,
    required String icon,
    required AppearanceSettings appearance,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    // HTML .slot: 120px @ bottom:15 -> .slot.active: 190px @ bottom:90.
    final diameter = (120 + (190 - 120) * t) * scale;
    final bottom = (15 + (90 - 15) * t) * scale;
    final borderWidth = 5 * t * scale;
    final iconSize = (64 + (78 - 64) * t) * scale;
    final iconOpacity = 0.92 + 0.08 * t;
    final iconColor = Color.lerp(appearance.bottomNavIconColor, appearance.bottomNavIconActiveColor, t)!;
    final cx = _slotX[key]!;

    return Positioned(
      left: cx * scale - diameter / 2,
      bottom: bottom,
      width: diameter,
      height: diameter,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: borderWidth > 0
                  ? Border.all(color: const Color(0xFFEEF3FF), width: borderWidth)
                  : null,
              gradient: t > 0
                  ? _activeButtonGradient(appearance.bottomNavHomeButtonColor, t)
                  : null,
              boxShadow: t > 0
                  ? [
                      BoxShadow(
                        color: appearance.bottomNavHomeButtonColor.withOpacity(.5 * t),
                        blurRadius: 22 * scale,
                        offset: Offset(0, 6 * scale),
                      ),
                      BoxShadow(
                        color: const Color(0xFF9646FF).withOpacity(.5 * t),
                        blurRadius: 30 * scale,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Opacity(
                opacity: iconOpacity,
                child: SvgPicture.string(
                  _withIconColor(icon, _hex(iconColor)),
                  width: iconSize,
                  height: iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// HTML `.slot.active` background:
/// `radial-gradient(circle at 38% 28%, #b478ff 0%, #8a3cf0 45%, #4a12b0 100%)`
/// tinted by [base] (the app's configurable home/active button color) and
/// cross-faded in by [t].
RadialGradient _activeButtonGradient(Color base, double t) {
  final hsl = HSLColor.fromColor(base);
  final lighter = hsl.withLightness((hsl.lightness + .18).clamp(0.0, 1.0)).toColor();
  final darker = hsl.withLightness((hsl.lightness - .22).clamp(0.0, 1.0)).toColor();
  final darkest = hsl.withLightness((hsl.lightness - .30).clamp(0.0, 1.0)).toColor();
  return RadialGradient(
    center: const Alignment(-.24, -.44), // "38% 28%" in CSS % coords -> Alignment
    radius: 1,
    colors: [
      Color.lerp(Colors.transparent, lighter, t)!,
      Color.lerp(Colors.transparent, base, t)!,
      Color.lerp(Colors.transparent, darker, t)!,
      Color.lerp(Colors.transparent, darkest, t)!,
    ],
    stops: const [0, .35, .75, 1],
  );
}

String _hex(Color c) => '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}';

/// Paints the HTML `<svg class="bottombar-svg">`: a full-width bar whose top
/// two corners are rounded (r=48) and whose bottom corners are square, with
/// a circular hole (r=122, centered on the top edge) punched out under every
/// currently-elevated slot. `slotT` carries each slot's 0..1 elevation so the
/// hole grows/shrinks and follows the same curve as the button itself.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.scale,
    required this.slotT,
    required this.backgroundColor,
    required this.borderColor,
    required this.glowColor,
    required this.opacity,
  });

  final double scale;
  final Map<NavKey, double> slotT;
  final Color backgroundColor;
  final Color borderColor;
  final Color glowColor;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final r = 48 * scale;
    final bar = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    var finalPath = bar;
    for (final entry in slotT.entries) {
      final t = entry.value;
      if (t <= 0.001) continue;
      final cx = _slotX[entry.key]! * scale;
      final hole = Path()..addOval(Rect.fromCircle(center: Offset(cx, 0), radius: 122 * scale * t));
      finalPath = Path.combine(ui.PathOperation.difference, finalPath, hole);
    }

    // HTML: filter: drop-shadow(0 -4px 16px rgba(0,5,25,.35)); applied after
    // the mask, so the shadow itself follows the perforated shape.
    canvas.save();
    canvas.translate(0, -4 * scale);
    canvas.drawPath(
      finalPath,
      Paint()
        ..color = const Color(0xFF00051A).withOpacity(.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * scale),
    );
    canvas.restore();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          backgroundColor.withOpacity((0.48 * opacity).clamp(0.0, 1.0)),
          backgroundColor.darken(0.12).withOpacity((0.52 * opacity).clamp(0.0, 1.0)),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(finalPath, fill);

    if (glowColor.opacity * opacity > 0) {
      canvas.drawPath(
        finalPath,
        Paint()
          ..color = glowColor.withOpacity((0.16 * opacity).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, 10 * scale),
      );
    }

    canvas.drawPath(
      finalPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scale
        ..color = borderColor.withOpacity((0.42 * opacity).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.glowColor != glowColor ||
      oldDelegate.opacity != opacity ||
      !_sameT(oldDelegate.slotT, slotT);

  static bool _sameT(Map<NavKey, double> a, Map<NavKey, double> b) {
    for (final k in _slotOrder) {
      if ((a[k] ?? 0) != (b[k] ?? 0)) return false;
    }
    return true;
  }
}

extension _ColorDarken on Color {
  Color darken([double amount = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    final l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }
}

String _withIconColor(String svg, String color) => svg.replaceAll('__COLOR__', color);

// Icon paths copied verbatim from preview.html's <button class="slot"> markup.
const _settingsSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="__COLOR__"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/></svg>';
const _voiceSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="__COLOR__"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>';
const _voiceMutedSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="__COLOR__" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9v6h4l5 5V4L7 9H3" fill="__COLOR__" stroke="none"/><path d="M16 9l5 5M21 9l-5 5"/></svg>';
const _starSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="__COLOR__" stroke-width="1.6" stroke-linejoin="round"><path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>';
const _searchSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="__COLOR__" stroke="__COLOR__"><path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>';
const _homeSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="__COLOR__" stroke="__COLOR__" stroke-width="6" stroke-linejoin="round"><path d="M50 16L90 50H80V86H60V62H40V86H20V50H10Z"/></svg>';
