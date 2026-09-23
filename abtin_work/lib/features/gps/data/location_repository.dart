import 'dart:async';
import '../../../core/permissions/location_permission_flow.dart';
import 'location_service.dart';

/// Thin repository layer between [LocationService] and the rest of the app.
/// UI/controllers should depend on this, not on [LocationService] directly.
class LocationRepository {
  final LocationService _service;
  final Future<LocationReadiness> Function() _ensureReady;

  LocationRepository(this._service,
      {Future<LocationReadiness> Function()? ensureReady})
      : _ensureReady = ensureReady ?? LocationPermissionFlow.ensureReady;

  Stream<VehiclePosition> get positionStream => _service.stream;
  Stream<LocationState> get stateStream => _service.stateStream;
  LocationState get state => _service.state;

  bool _started = false;

  Future<LocationReadiness> start() async {
    final readiness = await _ensureReady();
    if (readiness == LocationReadiness.ready && !_started) {
      _started = true;
      _service.start();
    }
    return readiness;
  }

  void pause() {
    _started = false;
    _service.stop();
  }

  void dispose() => _service.dispose();
}
