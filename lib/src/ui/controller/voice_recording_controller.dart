import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/voice_message_data.dart';

/// Finite state machine of the voice recorder.
///
/// - `idle`: nothing happening, ready to record.
/// - `recording`: user is actively recording (long-press held).
/// - `locked`: recording continues hands-free (user slid up to lock).
/// - `preListen`: recording stopped, user is previewing before sending.
enum VoiceRecordingState { idle, recording, locked, preListen }

/// Result of [VoiceRecordingController.startRecording].
///
/// `permissionJustGranted` is returned when the OS permission dialog was
/// shown during this call and the user accepted: instead of starting to
/// record (which would leave the UI in a state where the user cannot
/// interact with the recording because the long-press has already ended),
/// we abort and let the user trigger a new recording with another tap.
enum StartRecordingResult {
  started,
  alreadyRunning,
  permissionDenied,
  permissionJustGranted,
}

const _kPermissionDialogThreshold = Duration(milliseconds: 300);

const _kMinDuration = Duration(seconds: 1);
const _kAmplitudeSampleInterval = Duration(milliseconds: 100);
const _kMaxWaveformSamples = 200;

/// Drives the voice-message recorder UI: permission flow, recording state,
/// amplitude sampling for the waveform, and pre-listen playback.
class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController({
    this.maxDuration = const Duration(minutes: 15),
    @visibleForTesting AudioRecorder? recorder,
    @visibleForTesting AudioPlayer? preListenPlayer,
    @visibleForTesting String? tempDirectoryPath,
  }) : _recorder = recorder ?? AudioRecorder(),
       _preListenPlayer = preListenPlayer ?? AudioPlayer(),
       _tempDirectoryPath = tempDirectoryPath;

  final Duration maxDuration;
  final AudioRecorder _recorder;
  final AudioPlayer _preListenPlayer;
  final String? _tempDirectoryPath;

  VoiceRecordingState _state = VoiceRecordingState.idle;
  Duration _currentDuration = Duration.zero;
  final List<double> _liveWaveform = [];
  String? _recordingPath;
  Timer? _durationTimer;
  Timer? _amplitudeTimer;
  bool _isPaused = false;
  StreamSubscription<Duration>? _preListenPositionSub;
  StreamSubscription<Duration?>? _preListenDurationSub;
  StreamSubscription<PlayerState>? _preListenStateSub;

  VoiceRecordingState get state => _state;
  Duration get currentDuration => _currentDuration;
  List<double> get liveWaveform => List.unmodifiable(_liveWaveform);
  bool get isPaused => _isPaused;
  bool get isPreListening =>
      _state == VoiceRecordingState.preListen && _preListenPlayer.playing;
  Duration get preListenPosition => _preListenPlayer.position;
  Duration? get preListenDuration => _preListenPlayer.duration;

  bool _permissionDialogShown = false;

  Future<StartRecordingResult> startRecording() async {
    if (_state != VoiceRecordingState.idle) {
      return StartRecordingResult.alreadyRunning;
    }

    final stopwatch = Stopwatch()..start();
    final hasPermission = await _recorder.hasPermission();
    stopwatch.stop();

    final dialogLikelyShown = stopwatch.elapsed > _kPermissionDialogThreshold;

    if (!hasPermission) {
      if (dialogLikelyShown) _permissionDialogShown = true;
      return StartRecordingResult.permissionDenied;
    }

    // First time the OS dialog was shown and the user accepted: don't
    // start recording immediately because the long-press is already gone.
    // Mark the flag so subsequent calls don't trigger the same heuristic.
    if (dialogLikelyShown && !_permissionDialogShown) {
      _permissionDialogShown = true;
      return StartRecordingResult.permissionJustGranted;
    }
    _permissionDialogShown = true;

    final dirPath = _tempDirectoryPath ?? (await getTemporaryDirectory()).path;
    _cleanupResidualFiles(dirPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _recordingPath = '$dirPath/voice_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _recordingPath!,
    );

    _currentDuration = Duration.zero;
    _liveWaveform.clear();
    _isPaused = false;
    _state = VoiceRecordingState.recording;

    _startTimers();

    notifyListeners();
    return StartRecordingResult.started;
  }

  void _startTimers() {
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _currentDuration += const Duration(seconds: 1);
      if (_currentDuration >= maxDuration) {
        if (_state == VoiceRecordingState.recording) {
          lockRecording();
        } else {
          _stopTimers();
          notifyListeners();
        }
        return;
      }
      notifyListeners();
    });

    _amplitudeTimer = Timer.periodic(_kAmplitudeSampleInterval, (_) async {
      try {
        final amplitude = await _recorder.getAmplitude();
        final normalized = _normalizeAmplitude(amplitude.current);
        _liveWaveform.add(normalized);
        notifyListeners();
      } catch (_) {}
    });
  }

  void lockRecording() {
    if (_state != VoiceRecordingState.recording) return;
    _state = VoiceRecordingState.locked;
    notifyListeners();
  }

  Future<void> pauseRecording() async {
    if (_state != VoiceRecordingState.locked || _isPaused) return;
    _stopTimers();
    try {
      await _recorder.pause();
    } catch (_) {}
    _isPaused = true;
    notifyListeners();
  }

  Future<void> resumeRecording() async {
    if (_state != VoiceRecordingState.locked || !_isPaused) return;
    try {
      await _recorder.resume();
    } catch (_) {}
    _isPaused = false;
    _startTimers();
    notifyListeners();
  }

  Future<VoiceMessageData?> stopRecording() async {
    if (_state != VoiceRecordingState.recording) return null;
    return _finalizeRecording();
  }

  Future<void> cancelRecording() async {
    _stopTimers();
    if (_state == VoiceRecordingState.preListen) {
      await _preListenPlayer.stop();
    }
    _detachPreListenStreams();
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      await _recorder.stop();
    }
    _cleanupFile();
    _state = VoiceRecordingState.idle;
    _currentDuration = Duration.zero;
    _liveWaveform.clear();
    _isPaused = false;
    notifyListeners();
  }

  Future<void> startPreListen() async {
    // If we're already in pre-listen, treat the call as "replay": rewind to
    // start when the previous playback finished and play again. This is what
    // the play button in the pre-listen UI reuses for repeated playbacks.
    if (_state == VoiceRecordingState.preListen) {
      try {
        if (_preListenPlayer.processingState == ProcessingState.completed) {
          await _preListenPlayer.seek(Duration.zero);
        }
        await _preListenPlayer.play();
      } catch (_) {}
      notifyListeners();
      return;
    }

    if (_state != VoiceRecordingState.locked) return;

    _stopTimers();
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      await _recorder.stop();
    }

    _isPaused = false;
    _state = VoiceRecordingState.preListen;

    if (_recordingPath != null) {
      _attachPreListenStreams();
      await _preListenPlayer.setFilePath(_recordingPath!);
      _preListenPlayer.play();
    }
    notifyListeners();
  }

  Future<void> stopPreListen() async {
    if (_state != VoiceRecordingState.preListen) return;
    await _preListenPlayer.pause();
    notifyListeners();
  }

  void _attachPreListenStreams() {
    _detachPreListenStreams();
    _preListenPositionSub = _preListenPlayer.positionStream.listen((_) {
      notifyListeners();
    });
    _preListenDurationSub = _preListenPlayer.durationStream.listen((_) {
      notifyListeners();
    });
    _preListenStateSub = _preListenPlayer.playerStateStream.listen((
      state,
    ) async {
      if (state.processingState == ProcessingState.completed) {
        try {
          await _preListenPlayer.pause();
          await _preListenPlayer.seek(Duration.zero);
        } catch (_) {}
      }
      notifyListeners();
    });
  }

  void _detachPreListenStreams() {
    _preListenPositionSub?.cancel();
    _preListenPositionSub = null;
    _preListenDurationSub?.cancel();
    _preListenDurationSub = null;
    _preListenStateSub?.cancel();
    _preListenStateSub = null;
  }

  Future<VoiceMessageData?> confirmSend() async {
    if (_state == VoiceRecordingState.preListen) {
      await _preListenPlayer.stop();
      _detachPreListenStreams();
      final data = await _buildVoiceMessageData();
      _resetState();
      return data;
    }
    if (_state == VoiceRecordingState.locked) {
      return _finalizeRecording();
    }
    return null;
  }

  Future<VoiceMessageData?> _finalizeRecording() async {
    _stopTimers();
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      await _recorder.stop();
    }

    if (_currentDuration < _kMinDuration) {
      _cleanupFile();
      _resetState();
      return null;
    }

    final data = await _buildVoiceMessageData();
    _resetState();
    return data;
  }

  void _resetState() {
    _state = VoiceRecordingState.idle;
    _currentDuration = Duration.zero;
    _liveWaveform.clear();
    _isPaused = false;
    notifyListeners();
  }

  Future<VoiceMessageData?> _buildVoiceMessageData() async {
    if (_recordingPath == null) return null;

    final file = File(_recordingPath!);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    final waveform = _subsampleWaveform();
    final duration = _currentDuration.inMilliseconds > 0
        ? _currentDuration
        : Duration(
            milliseconds:
                waveform.length * _kAmplitudeSampleInterval.inMilliseconds,
          );

    _cleanupFile();

    return VoiceMessageData(
      audioBytes: Uint8List.fromList(bytes),
      duration: duration,
      waveform: waveform,
    );
  }

  List<int> _subsampleWaveform() {
    if (_liveWaveform.isEmpty) return [];

    if (_liveWaveform.length <= _kMaxWaveformSamples) {
      return _liveWaveform.map((v) => (v * 100).round().clamp(0, 100)).toList();
    }

    final result = <int>[];
    final step = _liveWaveform.length / _kMaxWaveformSamples;
    for (var i = 0; i < _kMaxWaveformSamples; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, _liveWaveform.length);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += _liveWaveform[j];
      }
      final avg = sum / (end - start);
      result.add((avg * 100).round().clamp(0, 100));
    }
    return result;
  }

  double _normalizeAmplitude(double dbValue) {
    // dbValue is typically -160 (silence) to 0 (max)
    const minDb = -60.0;
    const maxDb = 0.0;
    final clamped = dbValue.clamp(minDb, maxDb);
    return (clamped - minDb) / (maxDb - minDb);
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
  }

  void _cleanupResidualFiles(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        if (entity is File &&
            entity.path.contains('voice_') &&
            entity.path.endsWith('.m4a')) {
          entity.deleteSync();
        }
      }
    } catch (_) {}
  }

  void _cleanupFile() {
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
      _recordingPath = null;
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _detachPreListenStreams();
    _preListenPlayer.dispose();
    _recorder.dispose();
    _cleanupFile();
    super.dispose();
  }
}
