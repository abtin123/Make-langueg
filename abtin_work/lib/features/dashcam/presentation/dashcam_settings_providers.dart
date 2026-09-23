import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../domain/dashcam_settings.dart';

export '../domain/dashcam_settings.dart';

const _keyDashCamSettings = 'dashcam_settings_v1';

final dashCamSettingsProvider =
    StateNotifierProvider<DashCamSettingsNotifier, DashCamSettings>(
  (ref) => DashCamSettingsNotifier(ref),
);

class DashCamSettingsNotifier extends StateNotifier<DashCamSettings> {
  DashCamSettingsNotifier(this._ref) : super(const DashCamSettings());

  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  /// از appSettingsInitProvider در استارتاپ صدا زده می‌شود.
  Future<void> load() async {
    final raw = await _repo.getValue(_keyDashCamSettings);
    if (raw != null && raw.isNotEmpty) {
      state = DashCamSettings.deserialize(raw);
    }
  }

  Future<void> _persist() async {
    await _repo.setValue(_keyDashCamSettings, state.serialize());
  }

  Future<void> update(DashCamSettings Function(DashCamSettings) fn) async {
    state = fn(state);
    await _persist();
  }
}
