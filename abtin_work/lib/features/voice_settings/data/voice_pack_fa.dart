library;

/// نگاشت مانور واقعی به cueهای داخل فایل ABV یک‌تکه. این کلاس هرگز فاصله را
/// به متن یا نام فایل تبدیل نمی‌کند؛ فاصله فقط روی رابط نقشه دیده می‌شود.
class VoicePackFa {
  VoicePackFa._();

  static String cueForManeuver(
      {required String type, String? modifier, int? exit}) {
    final normalizedType = type.toLowerCase();
    final normalizedModifier = modifier?.toLowerCase() ?? '';
    if (normalizedType == 'arrive') return 'arrived_destination';
    if (normalizedType == 'depart') return 'route_found';
    if (normalizedType == 'roundabout' || normalizedType == 'rotary') {
      if (exit != null && exit >= 1 && exit <= 20) {
        return 'roundabout_take_exit_$exit';
      }
      return 'roundabout_take_exit_next';
    }
    if (normalizedModifier.contains('uturn')) return 'u_turn';
    if (normalizedType == 'new name' || normalizedType == 'continue')
      return 'continue_straight';
    if (normalizedType == 'on ramp' ||
        normalizedType == 'off ramp' ||
        normalizedType == 'end of road') return 'exit_highway';
    if (normalizedType == 'merge' || normalizedType == 'fork') {
      return normalizedModifier.contains('left') ? 'keep_left' : 'keep_right';
    }
    if (normalizedModifier.contains('sharp left')) return 'turn_sharp_left';
    if (normalizedModifier.contains('sharp right')) return 'turn_sharp_right';
    if (normalizedModifier.contains('slight left')) return 'turn_slight_left';
    if (normalizedModifier.contains('slight right')) return 'turn_slight_right';
    if (normalizedModifier.contains('left')) return 'turn_left';
    if (normalizedModifier.contains('right')) return 'turn_right';
    return 'continue_straight';
  }

  static const String arrived = 'arrived_destination';

  /// دقیقاً همان متن ثابت موجود در JSON بستهٔ ABV که کارت ناوبری نیز باید
  /// نمایش دهد. نام خیابان و فاصله عمداً وارد این متن نمی‌شوند؛ آن‌ها پویا
  /// هستند و در فایل صوتی یک‌تکه cue مستقل ندارند.
  static String textForCue(String cue) {
    const texts = <String, String>{
      'route_found': 'مسیر جدید یافت شد',
      'recalculating_route': 'مسیر در حال محاسبه مجدد است',
      'off_route': 'شما از مسیر خارج شدید',
      'arrived_destination': 'به مقصد رسیدید',
      'turn_left': 'به چپ بپیچید',
      'turn_right': 'به راست بپیچید',
      'turn_sharp_left': 'به شدت به چپ بپیچید',
      'turn_sharp_right': 'به شدت به راست بپیچید',
      'turn_slight_left': 'کمی به چپ بپیچید',
      'turn_slight_right': 'کمی به راست بپیچید',
      'u_turn': 'دور بزنید',
      'continue_straight': 'مستقیم ادامه دهید',
      'keep_left': 'در مسیر چپ بمانید',
      'keep_right': 'در مسیر راست بمانید',
      'exit_highway': 'از بزرگراه خارج شوید',
      'roundabout_take_exit_next': 'در میدان، از خروجی بعدی خارج شوید',
    };
    if (cue.startsWith('roundabout_take_exit_')) {
      final exit = int.tryParse(cue.substring('roundabout_take_exit_'.length));
      const ordinals = <String>[
        '',
        'اول',
        'دوم',
        'سوم',
        'چهارم',
        'پنجم',
        'ششم',
        'هفتم',
        'هشتم',
        'نهم',
        'دهم'
      ];
      if (exit != null && exit > 0 && exit < ordinals.length) {
        return 'در میدان، از خروجی ${ordinals[exit]} خارج شوید';
      }
    }
    return texts[cue] ?? 'مستقیم ادامه دهید';
  }
}
