import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:just_audio/just_audio.dart';

import 'voice_pack_catalog.dart';

enum VoiceState { playing, stopped }

/// راهنمای مسیر از یک فایل دانلودی واحد پخش می‌شود. هر فرمان فقط با seek به
/// بازهٔ cue خودش اجرا می‌شود؛ فایل‌های جمله‌ای و چسباندن صوت در دستگاه نداریم.
class VoiceService extends ChangeNotifier {
  VoiceService({VoicePackService? packs})
      : _packs = packs ?? VoicePackService() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) _finish();
    });
    _player.positionStream.listen(_stopAtCueBoundary);
  }

  final VoicePackService _packs;
  final AudioPlayer _player = AudioPlayer();
  VoiceState _state = VoiceState.stopped;
  bool _disposed = false;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  int _generation = 0;
  final List<_VoiceRequest> _queue = <_VoiceRequest>[];
  bool _queueRunning = false;
  final Map<String, DateTime> _lastQueuedAt = <String, DateTime>{};
  Timer? _cueStopTimer;
  Duration? _activeCueEnd;
  int _activeCueGeneration = 0;
  String? _activeDownloadedVoice;
  String? _activeDownloadedAlert;
  String? _loadedAudioPath;
  Future<void>? _activePreload;

  VoiceState get state => _state;

  void setActiveDownloadedVoice(String? fileName) {
    _activeDownloadedVoice = fileName;
    if (fileName != null && fileName.isNotEmpty) {
      _activePreload = _preloadVoiceBundle(fileName);
      unawaited(_activePreload!);
    } else {
      _activePreload = null;
    }
  }

  void setActiveDownloadedAlert(String? fileName) =>
      _activeDownloadedAlert = fileName;

  /// نمونه نیز هرگز فایل کامل نیست: یک cue قابل‌فهم از همان ABV حداکثر برای
  /// چند ثانیه پخش می‌شود و با همان guard انتهای cue متوقف خواهد شد.
  Future<bool> playDownloadedSample(String fileName) =>
      _playShortPreviewCue(fileName);

  /// صدای هشدارِ انتخاب‌شده هم فقط از cue تعریف‌شده در manifest خوانده می‌شود.
  Future<bool> playDownloadedAlert(String fileName) =>
      _playShortPreviewCue(fileName, preferredCue: 'speed_camera_ahead');

  Future<void> playAlert() async {
    final selected = _activeDownloadedAlert;
    if (selected != null && selected.isNotEmpty) {
      await _playCueFromFile(selected, 'speed_camera_ahead');
    }
  }

  /// پخش دقیق یک cue از فایل واحد انتخاب‌شده. در بسته‌های قدیمی که cue ندارند
  /// هیچ صدایی پخش نمی‌شود تا به‌اشتباه کل فایل به‌جای یک فرمان شنیده نشود.
  Future<bool> playCue(String cue) async {
    final selected = _activeDownloadedVoice;
    if (selected == null || selected.isEmpty) return false;

    // Navigation voice is serialized: a noisy GPS update may request the same
    // cue several times in a few hundred milliseconds. Keep one request per
    // cue during the lock window and let urgent cues jump ahead of routine
    // announcements.
    final key = '$selected|$cue';
    final now = DateTime.now();
    final last = _lastQueuedAt[key];
    if (last != null && now.difference(last) < const Duration(seconds: 7)) {
      return false;
    }
    _lastQueuedAt[key] = now;

    final request = _VoiceRequest(
      fileName: selected,
      cue: cue,
      priority: _voicePriority(cue),
    );
    _queue.add(request);
    _queue.sort((a, b) => b.priority.compareTo(a.priority));
    unawaited(_drainVoiceQueue());
    return true;
  }

  int _voicePriority(String cue) {
    final c = cue.toLowerCase();
    if (c.contains('off_route') || c.contains('recalculating') ||
        c.contains('arriv')) return 100;
    if (c.contains('roundabout') || c.contains('uturn')) return 90;
    if (c.contains('turn')) return 80;
    if (c.contains('continue') || c.contains('straight')) return 50;
    return 40;
  }

  Future<void> _drainVoiceQueue() async {
    if (_queueRunning || _disposed) return;
    _queueRunning = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final request = _queue.removeAt(0);
        await _playCueFromFile(request.fileName, request.cue);
      }
    } finally {
      _queueRunning = false;
    }
  }

  Future<bool> _playShortPreviewCue(
    String fileName, {
    String? preferredCue,
  }) async {
    final bundle = await _packs.playableVoiceBundle(fileName);
    if (bundle == null || bundle.cues.isEmpty) return false;
    const candidates = <String>[
      'sample',
      'continue_straight',
      'straight',
      'turn_right',
      'turn_left',
      'speed_camera_ahead',
    ];
    final cueName =
        preferredCue != null && bundle.cues.containsKey(preferredCue)
            ? preferredCue
            : candidates.firstWhere(
                bundle.cues.containsKey,
                orElse: () => bundle.cues.keys.first,
              );
    return _playCueFromFile(
      fileName,
      cueName,
      previewLimit: const Duration(seconds: 4),
    );
  }

  Future<bool> _playCueFromFile(
    String fileName,
    String cueName, {
    Duration? previewLimit,
  }) async {
    final generation = ++_generation;
    _cueStopTimer?.cancel();
    _activeCueEnd = null;
    try {
      if (fileName == _activeDownloadedVoice) await _activePreload;
      final bundle = await _packs.playableVoiceBundle(fileName);
      final cue = bundle?.cues[cueName];
      if (bundle == null || cue == null || generation != _generation)
        return false;
      await _player.stop();
      // فایل ABV فقط در اولین فرمان یا پس از تغییر صدا باز می‌شود. فرمان‌های
      // بعدی صرفاً seek روی decoder آماده‌اند و تاخیر ساخت/دانلود صوت ندارند.
      if (_loadedAudioPath != bundle.file.path) {
        await _player.setAudioSource(AudioSource.uri(bundle.file.uri));
        _loadedAudioPath = bundle.file.path;
      }
      if (generation != _generation) return false;
      await _player.setVolume(_volume);
      await _player.setSpeed(_playbackRate);
      await _player.seek(cue.start);
      final previewEndMs = cue.start.inMilliseconds +
          (previewLimit?.inMilliseconds ??
              (cue.end - cue.start).inMilliseconds);
      final limitedEnd = Duration(
        milliseconds: previewEndMs < cue.end.inMilliseconds
            ? previewEndMs
            : cue.end.inMilliseconds,
      );
      _activeCueEnd = limitedEnd;
      _activeCueGeneration = generation;
      await _player.play();
      _state = VoiceState.playing;
      _notify();
      final duration = limitedEnd - cue.start;
      final realDuration = Duration(
          milliseconds: (duration.inMilliseconds / _playbackRate).ceil());
      _cueStopTimer = Timer(
        realDuration + const Duration(milliseconds: 80),
        () => unawaited(_finishCueAtBoundary(generation)),
      );
      return true;
    } catch (error) {
      
      return false;
    }
  }

  /// علاوه بر timer، موقعیت واقعی decoder هم کنترل می‌شود تا پخش هیچ‌وقت از
  /// انتهای cue JSON عبور نکند؛ حتی با تغییر سرعت پخش یا تأخیر زمان‌سنج.
  void _stopAtCueBoundary(Duration position) {
    final end = _activeCueEnd;
    if (end == null || position < end || _activeCueGeneration != _generation)
      return;
    unawaited(_finishCueAtBoundary(_activeCueGeneration));
  }

  Future<void> _finishCueAtBoundary(int generation) async {
    if (generation != _generation || _activeCueEnd == null) return;
    _activeCueEnd = null;
    _cueStopTimer?.cancel();
    await _player.stop();
    _finish();
  }

  /// بستهٔ انتخاب‌شده را پس از انتخاب کاربر، پیش از شروع مسیریابی باز می‌کند.
  /// این فراخوانی عمداً await نمی‌شود تا UI تنظیمات مکث نکند؛ فرمان بعدی فقط
  /// روی decoder بازشده seek خواهد شد.
  Future<void> _preloadVoiceBundle(String fileName) async {
    try {
      final bundle = await _packs.playableVoiceBundle(fileName);
      if (bundle == null || _activeDownloadedVoice != fileName) return;
      if (_loadedAudioPath != bundle.file.path) {
        await _player.setAudioSource(AudioSource.uri(bundle.file.uri));
        _loadedAudioPath = bundle.file.path;
      }
    } catch (error) {
      // خطای preload نباید انتخاب بسته را باطل کند؛ _playCueFromFile در زمان
      // فرمان دوباره تلاش می‌کند و خطای واقعی را ثبت می‌کند.
      
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate.clamp(0.5, 2.0);
    await _player.setSpeed(_playbackRate);
  }

  Future<void> stop() async {
    _generation++;
    _cueStopTimer?.cancel();
    _activeCueEnd = null;
    await _player.stop();
    _finish();
  }

  void _finish() {
    _state = VoiceState.stopped;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cueStopTimer?.cancel();
    _activeCueEnd = null;
    _player.dispose();
    super.dispose();
  }
}

class _VoiceRequest {
  const _VoiceRequest({required this.fileName, required this.cue, required this.priority});
  final String fileName;
  final String cue;
  final int priority;
}
