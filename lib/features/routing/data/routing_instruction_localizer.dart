import '../../../core/localization/app_localizations.dart';

/// Converts neutral routing maneuvers into the currently selected language.
/// The language code is resolved at runtime so downloaded language packs work
/// without adding language-specific branches to the routing engine.
class RoutingInstructionLocalizer {
  const RoutingInstructionLocalizer._();

  static String text({
    required String languageCode,
    required String type,
    String? modifier,
    String? roadName,
    int? exit,
  }) {
    String tr(String key) => AppStrings.getForLanguage(languageCode, key);
    final road = roadName == null
        ? ''
        : ' ${tr('route_road_prefix').replaceAll('{road}', roadName)}';
    String withRoad(String value) => value.replaceAll('{road}', road);

    final normalizedType = type.trim().toLowerCase().replaceAll('-', ' ');
    final normalizedModifier = (modifier ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
    final direction = switch (normalizedModifier) {
      'left' => tr('route_maneuver_turn_left'),
      'right' => tr('route_maneuver_turn_right'),
      'slight left' => tr('route_maneuver_slight_left'),
      'slight right' => tr('route_maneuver_slight_right'),
      'sharp left' => tr('route_maneuver_sharp_left'),
      'sharp right' => tr('route_maneuver_sharp_right'),
      'uturn' || 'u turn' || 'uturn left' || 'uturn right' || 'u turn left' || 'u turn right' => tr('route_maneuver_uturn'),
      'straight' => tr('route_maneuver_straight'),
      _ => tr('route_maneuver_continue'),
    };

    return switch (normalizedType) {
      'depart' => withRoad(tr('route_maneuver_depart')),
      'arrive' => tr('route_maneuver_arrive'),
      'roundabout' || 'rotary' => exit == null
          ? withRoad(tr('route_maneuver_roundabout'))
          : tr('route_maneuver_roundabout_exit')
              .replaceAll('{exit}', '$exit')
              .replaceAll('{road}', road),
      'merge' => withRoad(tr('route_maneuver_merge')),
      'fork' || 'end of road' => withRoad(direction),
      'on ramp' => withRoad(tr('route_maneuver_on_ramp')),
      'off ramp' => withRoad(tr('route_maneuver_off_ramp')),
      'continue' ||
      'new name' ||
      'notification' =>
        withRoad(tr('route_maneuver_straight')),
      _ => withRoad(direction),
    };
  }
}
