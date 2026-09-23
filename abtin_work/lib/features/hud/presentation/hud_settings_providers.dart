import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../domain/hud_settings.dart';

export '../domain/hud_settings.dart';

const _keyHudSettings = 'hud_settings_v1';

final hudSettingsProvider =
    StateNotifierProvider<HudSettingsNotifier, HudSettings>(
  (ref) => HudSettingsNotifier(ref),
);

class HudSettingsNotifier extends StateNotifier<HudSettings> {
  HudSettingsNotifier(this._ref) : super(const HudSettings());

  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  /// از appSettingsInitProvider در استارتاپ صدا زده می‌شود.
  Future<void> load() async {
    final raw = await _repo.getValue(_keyHudSettings);
    if (raw != null && raw.isNotEmpty) {
      state = HudSettings.deserialize(raw);
    }
  }

  Future<void> _persist() async {
    await _repo.setValue(_keyHudSettings, state.serialize());
  }

  Future<void> update(HudSettings Function(HudSettings) fn) async {
    state = fn(state);
    await _persist();
  }
}
