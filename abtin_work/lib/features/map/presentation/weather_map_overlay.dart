import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../gps/data/location_service.dart';
import '../../gps/presentation/gps_providers.dart';
import '../../settings/presentation/appearance_settings_providers.dart';

final weatherSnapshotProvider =
    StateNotifierProvider<WeatherSnapshotNotifier, WeatherSnapshot?>((ref) {
  return WeatherSnapshotNotifier(ref);
});

class WeatherSnapshot {
  const WeatherSnapshot(
      {required this.temperature, required this.code, this.airQualityIndex});
  final double temperature;
  final int code;
  final int? airQualityIndex;

  String get condition {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    return '⛈️';
  }
}

class WeatherSnapshotNotifier extends StateNotifier<WeatherSnapshot?> {
  WeatherSnapshotNotifier(this.ref) : super(null) {
    ref.listen<AsyncValue<VehiclePosition>>(vehiclePositionProvider,
        (previous, next) {
      if (next.hasValue) unawaited(_refresh());
    });
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _refresh());
    _refresh();
  }

  final Ref ref;
  Timer? _timer;
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    final position = ref.read(vehiclePositionProvider).valueOrNull;
    if (position == null) return;
    _busy = true;
    try {
      final query = {
        'latitude': position.lat.toString(),
        'longitude': position.lng.toString(),
        'current': 'temperature_2m,weather_code',
        'temperature_unit': 'celsius',
      };
      final airQuery = {
        'latitude': position.lat.toString(),
        'longitude': position.lng.toString(),
        'current': 'us_aqi',
      };
      final responses = await Future.wait([
        http
            .get(Uri.https('api.open-meteo.com', '/v1/forecast', query))
            .timeout(const Duration(seconds: 8)),
        http
            .get(Uri.https(
                'air-quality-api.open-meteo.com', '/v1/air-quality', airQuery))
            .timeout(const Duration(seconds: 8)),
      ]);
      if (responses[0].statusCode != 200) return;
      final forecast = jsonDecode(responses[0].body);
      final current = forecast is Map ? forecast['current'] : null;
      if (current is! Map) return;
      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final code = (current['weather_code'] as num?)?.toInt();
      if (temp == null || code == null || !mounted) return;
      int? aqi;
      if (responses[1].statusCode == 200) {
        final air = jsonDecode(responses[1].body);
        final airCurrent = air is Map ? air['current'] : null;
        final rawAqi = airCurrent is Map ? airCurrent['us_aqi'] : null;
        aqi = rawAqi is num ? rawAqi.round() : null;
      }
      state = WeatherSnapshot(
        temperature: temp,
        code: code,
        airQualityIndex: aqi,
      );
    } catch (_) {
      // Weather/AQI are optional and must never affect navigation.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class WeatherMapOverlay extends ConsumerWidget {
  const WeatherMapOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    final weatherEnabled = ref.watch(weatherWidgetEnabledProvider);
    final aqiEnabled = ref.watch(airQualityWidgetEnabledProvider);
    final snapshot = ref.watch(weatherSnapshotProvider);
    if (!weatherEnabled && !aqiEnabled) return const SizedBox.shrink();
    final top = appearance.weatherVerticalPercent.clamp(0.0, 100.0);
    final left = appearance.weatherHorizontalPercent.clamp(0.0, 100.0);
    final textColor = appearance.weatherTextColor;

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          MediaQuery.of(context).padding.top + 12,
          12,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Align(
          alignment: Alignment(left / 50.0 - 1, top / 50.0 - 1),
          child: Transform.scale(
            scale: (appearance.weatherSize / 100.0).clamp(0.7, 1.5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: appearance.weatherBgColor
                    .withOpacity(appearance.weatherBgOpacity),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (weatherEnabled) ...[
                    Text(snapshot?.condition ?? '☁️',
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 2),
                    Text(
                        snapshot == null
                            ? '—'
                            : '${snapshot.temperature.round()}°C',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ],
                  if (weatherEnabled && aqiEnabled) const SizedBox(height: 6),
                  if (aqiEnabled) ...[
                    const Icon(Icons.air_rounded,
                        size: 19, color: Color(0xFF56D6A0)),
                    const SizedBox(height: 2),
                    Text('AQI ${snapshot?.airQualityIndex ?? '—'}',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
