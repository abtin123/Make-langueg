import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/voice_service.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../../settings/data/settings_repository.dart';
import 'voice_pack_providers.dart';

final ttsServiceProvider = ChangeNotifierProvider<VoiceService>((ref) {
  final service = VoiceService();
  service.setActiveDownloadedVoice(ref.read(activeVoicePackProvider));
  service.setActiveDownloadedAlert(ref.read(alertVoicePackProvider));
  ref.listen<String?>(activeVoicePackProvider, (_, next) {
    service.setActiveDownloadedVoice(next);
  });
  ref.listen<String?>(alertVoicePackProvider, (_, next) {
    service.setActiveDownloadedAlert(next);
  });
  ref.onDispose(service.dispose);
  return service;
});

final ttsStateProvider = StateProvider<VoiceState>((ref) => VoiceState.stopped);

final ttsRateProvider =
    StateNotifierProvider<_DoubleSettingNotifier, double>((ref) {
  return _DoubleSettingNotifier(
    ref.watch(settingsRepositoryProvider),
    SettingsRepository.keyVoiceRate,
    1.0,
  );
});

final ttsVolumeProvider =
    StateNotifierProvider<_DoubleSettingNotifier, double>((ref) {
  return _DoubleSettingNotifier(
    ref.watch(settingsRepositoryProvider),
    SettingsRepository.keyVoiceVolume,
    0.75,
  );
});

class _DoubleSettingNotifier extends StateNotifier<double> {
  _DoubleSettingNotifier(this.repo, this.key, double fallback)
      : super(fallback) {
    _load(fallback);
  }
  final SettingsRepository repo;
  final String key;
  Future<void> _load(double fallback) async {
    state = await repo.getDouble(key, fallback: fallback);
  }

  Future<void> set(double value) async {
    state = value;
    await repo.setDouble(key, value);
  }
}

final voiceFirstAlertDistanceProvider =
    StateNotifierProvider<_DoubleSettingNotifier, double>((ref) {
  return _DoubleSettingNotifier(
    ref.watch(settingsRepositoryProvider),
    SettingsRepository.keyVoiceFirstAlertDistanceMeters,
    250.0,
  );
});

final ttEnabledProvider =
    StateNotifierProvider<_BoolSettingNotifier, bool>((ref) {
  return _BoolSettingNotifier(ref.watch(settingsRepositoryProvider),
      SettingsRepository.keyVoiceEnabled, true);
});

final alertsVoiceEnabledProvider =
    StateNotifierProvider<_BoolSettingNotifier, bool>((ref) {
  return _BoolSettingNotifier(ref.watch(settingsRepositoryProvider),
      SettingsRepository.keyAlertsVoiceEnabled, true);
});

class _BoolSettingNotifier extends StateNotifier<bool> {
  _BoolSettingNotifier(this.repo, this.key, bool fallback) : super(fallback) {
    _load(fallback);
  }
  final SettingsRepository repo;
  final String key;
  Future<void> _load(bool fallback) async {
    state = await repo.getBool(key, fallback: fallback);
  }

  Future<void> set(bool value) async {
    state = value;
    await repo.setBool(key, value);
  }
}
