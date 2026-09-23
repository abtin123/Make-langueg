import 'package:go_router/go_router.dart';

import '../../features/map/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/map_settings_screen.dart';
import '../../features/settings/presentation/marker_settings_screen.dart';
import '../../features/settings/presentation/appearance_settings_screen.dart';
import '../../features/settings/presentation/route_settings_screen.dart';
import '../../features/dashcam/presentation/dashcam_settings_screen.dart';
import '../../features/hud/presentation/hud_settings_screen.dart';
import '../../features/hud/presentation/hud_display_screen.dart';
import '../../features/voice_settings/presentation/voice_settings_screen.dart';
import '../../features/saved_places/presentation/saved_places_screen.dart';
import '../../features/language_settings_hub/language_hub_screen.dart';
import '../../features/debug/presentation/abm_log_screen.dart';

bool _isExternalNavigationUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'geo' || scheme == 'google.navigation' || scheme == 'abtin') {
    return true;
  }
  if (scheme == 'https') {
    final host = uri.host.toLowerCase();
    final mapsHost = host == 'google.com' ||
        host == 'www.google.com' ||
        host == 'maps.google.com' ||
        host == 'maps.app.goo.gl';
    return mapsHost &&
        (uri.path.toLowerCase().startsWith('/maps') ||
            uri.queryParameters.containsKey('destination') ||
            uri.queryParameters.containsKey('q') ||
            uri.queryParameters.containsKey('query'));
  }
  return false;
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  // Android delivers geo:/google.navigation:/abtin: links as the platform
  // route name too. They are data for DeepLinkService, not go_router pages.
  // Redirecting them to '/' prevents the default `Page Not Found / GoException`
  // screen from winning the cold-start race while AppLinks parses the same URI.
  redirect: (context, state) {
    return _isExternalNavigationUri(state.uri) ? '/' : null;
  },
  // Final safety net: even if a platform/plugin delivers a navigation URI in
  // a form that bypasses the redirect pass, never expose go_router's raw
  // exception page to the driver. DeepLinkService still consumes the URI.
  errorBuilder: (context, state) => const HomeScreen(),
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
        path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/map-settings',
      builder: (context, state) => const MapSettingsScreen(),
    ),
    GoRoute(
      path: '/marker-settings',
      builder: (context, state) => const MarkerSettingsScreen(),
    ),
    GoRoute(
      path: '/appearance-settings',
      builder: (context, state) => const AppearanceSettingsScreen(),
    ),
    GoRoute(
      path: '/route-settings',
      builder: (context, state) => const RouteSettingsScreen(),
    ),
    GoRoute(
      path: '/dashcam-settings',
      builder: (context, state) => const DashCamSettingsScreen(),
    ),
    GoRoute(
      path: '/hud-settings',
      builder: (context, state) => const HudSettingsScreen(),
    ),
    GoRoute(
      path: '/hud-display',
      builder: (context, state) => const HudDisplayScreen(),
    ),
    GoRoute(
      path: '/voice-settings',
      builder: (context, state) => const VoiceSettingsScreen(),
    ),
    GoRoute(
      path: '/saved-places',
      builder: (context, state) => const SavedPlacesScreen(),
    ),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const LanguageHubScreen(),
    ),
    GoRoute(
      path: '/abm-log',
      builder: (context, state) => const AbmLogScreen(),
    ),
  ],
);
