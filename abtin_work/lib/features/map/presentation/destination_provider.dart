import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abtin_maps/core/geo/geo_types.dart';

class SelectedDestination {
  final LatLng point;
  final String? label;

  /// اگر true باشد، صفحهٔ نقشه بلافاصله مسیریابی را شروع می‌کند.
  final bool autoStart;
  const SelectedDestination(this.point, {this.label, this.autoStart = false});
}

final selectedDestinationProvider =
    StateProvider<SelectedDestination?>((ref) => null);
