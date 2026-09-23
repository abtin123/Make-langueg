import 'dart:io';

import '../../../core/geo/geo_types.dart';
import 'location_service.dart';

/// Offline reading (opening the active .abm and querying its road vector
/// layer) has been removed from the app, so offline road-snapping can never
/// find road geometry and always reports "no snap".
class OfflineRoadSnapService {
  Future<VehiclePosition?> snap(VehiclePosition position, File? mapFile) async {
    return null;
  }

  Future<void> dispose() async {}
}
