import 'package:flutter/material.dart';

/// نگاشتِ نوع/modifier دستورِ راهنمایی (OSRM-style: turn/continue/roundabout/
/// arrive/depart/merge/fork/... + modifier left/right/slight/sharp/uturn/
/// straight) به آیکونِ جهت‌نمای مناسب.
///
/// این منطق دقیقاً همان چیزی است که در بنر ناوبریِ صفحه‌ی اصلی
/// (`_getInstructionIcon` در home_screen.dart) استفاده می‌شود؛ اینجا به‌صورت
/// یک تابعِ مشترک بیرون کشیده شده تا HUD هم به‌جای فلشِ ثابتِ «مستقیم»،
/// همان جهتِ واقعیِ پیچ/میدان را نشان دهد.
IconData hudManeuverIcon(String type, String? modifier) {
  final normalizedType = type.trim().toLowerCase().replaceAll('-', ' ');
  final normalizedModifier = (modifier ?? '').trim().toLowerCase().replaceAll('-', ' ').replaceAll('_', ' ');
  if (normalizedType == 'uturn' || normalizedModifier.contains('uturn') || normalizedModifier.contains('u turn')) {
    return normalizedModifier.contains('right')
        ? Icons.u_turn_right_rounded
        : Icons.u_turn_left_rounded;
  }
  switch (normalizedType) {
    case 'turn':
    case 'continue':
    case 'new name':
    case 'end of road':
      final m = normalizedModifier;
      if (m.contains('uturn') || m.contains('u turn')) {
        return m.contains('right')
            ? Icons.u_turn_right_rounded
            : Icons.u_turn_left_rounded;
      }
      if (m == 'sharp left') return Icons.turn_sharp_left_rounded;
      if (m == 'sharp right') return Icons.turn_sharp_right_rounded;
      if (m == 'slight left') return Icons.turn_slight_left_rounded;
      if (m == 'slight right') return Icons.turn_slight_right_rounded;
      if (m == 'left') return Icons.turn_left_rounded;
      if (m == 'right') return Icons.turn_right_rounded;
      if (m.contains('straight')) return Icons.straight_rounded;
      return Icons.straight_rounded;
    case 'arrive':
      return Icons.flag_rounded;
    case 'depart':
      return Icons.navigation_rounded;
    case 'merge':
      return Icons.merge_rounded;
    case 'on ramp':
      return Icons.call_merge_rounded;
    case 'off ramp':
      return Icons.exit_to_app_rounded;
    case 'fork':
      final m = modifier ?? '';
      if (m.contains('left')) return Icons.fork_left_rounded;
      if (m.contains('right')) return Icons.fork_right_rounded;
      return Icons.call_split_rounded;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
      final m = modifier ?? '';
      if (m.contains('left')) return Icons.roundabout_left_rounded;
      return Icons.roundabout_right_rounded;
    default:
      return Icons.straight_rounded;
  }
}

/// برای مواقعی که آیکونِ Material مناسب برای جهت وجود ندارد (مثلاً وقتی
/// می‌خواهیم فقط یک فلش را بچرخانیم)، این تابع زاویه‌ی چرخشِ تقریبی (رادیان)
/// را برمی‌گرداند تا با یک فلشِ ساده هم بشود همه‌ی جهت‌ها را نشان داد.
double hudManeuverRotationRadians(String type, String? modifier) {
  final m = modifier ?? '';
  if (type == 'arrive') return 0;
  if (m.contains('uturn')) return 3.14159;
  if (m.contains('sharp left')) return -1.5708 * 0.8;
  if (m.contains('sharp right')) return 1.5708 * 0.8;
  if (m.contains('slight left')) return -0.35;
  if (m.contains('slight right')) return 0.35;
  if (m.contains('left')) return -0.9;
  if (m.contains('right')) return 0.9;
  return 0;
}
