import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../models/voice_message_data.dart';
import '../utils/platform_support.dart';
// `dart:io` and `path_provider` live behind this conditional import so the
// package keeps a WASM-compatible import graph (pana penalises Web targets
// that transitively reach `dart:io`). The Web stub throws; the controller's
// `startRecording` short-circuits with `unsupported` before any of the
// helpers can be called on Web.
import '_voice_recorder_io.dart'
    if (dart.library.js_interop) '_voice_recorder_io_web.dart';

/// Finite state machine of the voice recorder.
///
/// - `idle`: nothing happening, ready to record.
/// - `recording`: user is actively recording (finger held down).
/// - `locked`: recording continues hands-free (user slid up to lock).
/// - `preListen`: recording stopped, user is previewing before sending.
enum VoiceRecordingState { idle, recording, locked, preListen }

/// Result of [VoiceRecordingController.startRecording].
enum StartRecordingResult {
  started,
  alreadyRunning,
  permissionDenied,
  unsupported,

  /// Nothing came of the attempt and nobody is left waiting for one: the
  /// touch that asked for the recording was already over by the time the
  /// platform recorder was about to be armed — in which case the platform
  /// audio session was never opened at all — or the controller was
  /// disposed while the recorder was still coming up.
  aborted,

  /// The platform refused to arm the recorder: the audio session could not
  /// be activated (a call in progress, another app holding the microphone)
  /// or a platform channel was missing. Nothing was captured and the
  /// controller is left idle, ready for the next attempt.
  failed,
}

const _kMinDuration = Duration(seconds: 1);
const _kMinCaptureDuration = Duration(milliseconds: 300);
const _kMinCaptureBytes = 1024;
const _kAmplitudeSampleInterval = Duration(milliseconds: 100);
const _kMaxWaveformSamples = 200;
const _kRevealDelay = Duration(milliseconds: 120);

/// Drives the voice-message recorder UI: permission flow, recording state,
/// amplitude sampling for the waveform, and pre-listen playback.
class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController({
    this.maxDuration = const Duration(minutes: 15),
    this.revealDelay = _kRevealDelay,
    @visibleForTesting AudioRecorder? recorder,
    @visibleForTesting AudioPlayer? preListenPlayer,
    @visibleForTesting String? tempDirectoryPath,
  }) : _recorder = recorder ?? AudioRecorder(),
       _preListenPlayer = preListenPlayer ?? AudioPlayer(),
       _tempDirectoryPath = tempDirectoryPath;

  /// Shortest touch worth turning into a voice message. A release below it
  /// discards the file and yields no [VoiceMessageData] — the composer
  /// reads this to tell a too-brief touch apart from a genuine failure and
  /// prompt the user instead of dropping the gesture in silence.
  ///
  /// Measured from the touch, not from the moment the platform recorder
  /// came up: the composer passes `heldFor` to [stopRecording]. Gating on
  /// [currentDuration] instead would make the real minimum "arming latency
  /// plus one second", so a touch held well over a second could still be
  /// thrown away with a message telling the user to hold longer.
  ///
  /// Asking for a recording is not the same as getting one, so this gate
  /// is paired with [minCaptureDuration] on the audio side.
  static const Duration minSendDuration = _kMinDuration;

  /// Shortest live capture worth turning into a voice message.
  ///
  /// [minSendDuration] answers "did the user ask for a recording?" and
  /// runs from the touch; this one answers "did the recorder make one?"
  /// and runs from the instant the platform recorder came up. Both have
  /// to be met. Arming can eat most of a second — Android waits on the
  /// Bluetooth manager, the first grant is slow — so a touch held just
  /// past the minimum can leave a file holding a few milliseconds of
  /// audio, or none at all: a capture that brief can fail to finalise its
  /// container, and the amplitude sampler never takes a sample, which
  /// used to produce a voice message labelled 00:00. Below this floor the
  /// file is dropped and [lastCaptureFailed] goes up, so the composer can
  /// report a recorder that did not deliver instead of blaming the user
  /// for a touch that was in fact long enough.
  static const Duration minCaptureDuration = _kMinCaptureDuration;

  final Duration maxDuration;

  /// How long a fresh recording is kept to itself before listeners are
  /// told about it.
  ///
  /// Capture starts on touch down — the recorder must not require a hold.
  /// The composer no longer waits for this window to swap to its recording
  /// row: it paints that row from the touch itself, driven by
  /// `MessageInputVoiceController.isPreparing`. What the window still buys
  /// is quiet while the recorder settles — the first waveform samples and
  /// duration ticks don't churn the UI mid-arming. The capture is
  /// unaffected: [state] is `recording` from the first millisecond and
  /// audio from that instant ends up in the file; only the notification
  /// waits. Set to [Duration.zero] to notify immediately.
  final Duration revealDelay;
  final AudioRecorder _recorder;
  final AudioPlayer _preListenPlayer;
  final String? _tempDirectoryPath;

  VoiceRecordingState _state = VoiceRecordingState.idle;
  Duration _currentDuration = Duration.zero;
  final List<double> _liveWaveform = [];
  String? _recordingPath;
  DateTime? _captureStartedAt;
  bool _lastCaptureFailed = false;
  bool _disposed = false;
  Timer? _durationTimer;
  Timer? _amplitudeTimer;
  Timer? _revealTimer;
  bool _isPaused = false;
  StreamSubscription<Duration>? _preListenPositionSub;
  StreamSubscription<Duration>? _preListenDurationSub;
  StreamSubscription<PlayerState>? _preListenStateSub;
  // audioplayers does not expose synchronous `playing`/`position`/`duration`
  // getters; we mirror them locally and update from the player's streams.
  bool _preListenPlaying = false;
  Duration _preListenPosition = Duration.zero;
  Duration? _preListenDuration;

  VoiceRecordingState get state => _state;

  /// Whether the last finalised capture produced nothing because the
  /// recorder failed to deliver usable audio — the platform refused to
  /// stop cleanly, the capture never outlived [minCaptureDuration], or the
  /// staged file came back missing or too small to hold any sound.
  ///
  /// Stays false when the capture was dropped because the touch was
  /// shorter than [minSendDuration]: that one is on the user, and the
  /// composer already has a prompt for it. Read right after
  /// [stopRecording] or [confirmSend] returns null to tell the two apart.
  bool get lastCaptureFailed => _lastCaptureFailed;

  Duration get currentDuration => _currentDuration;
  List<double> get liveWaveform => List.unmodifiable(_liveWaveform);
  bool get isPaused => _isPaused;
  bool get isPreListening =>
      _state == VoiceRecordingState.preListen && _preListenPlaying;
  Duration get preListenPosition => _preListenPosition;
  Duration? get preListenDuration => _preListenDuration;

  /// Starts capturing audio.
  ///
  /// [isStillWanted] is consulted at the last moment before the platform
  /// recorder is armed. Returning false yields
  /// [StartRecordingResult.aborted] without touching the recorder, which
  /// is what keeps a tap shorter than the arming latency from opening and
  /// closing the platform audio session — on iOS that cycle interrupts
  /// whatever the user was listening to.
  ///
  /// Never throws. Every arming step can (`hasPermission` and the temp
  /// directory lookup go through platform channels, and `record.start`
  /// throws on iOS when the audio session cannot be activated); an
  /// exception escaping here would leave the composer painting a recording
  /// row with nothing behind it, so failures come back as
  /// [StartRecordingResult.failed] with the controller left idle.
  ///
  /// A controller disposed while the recorder was coming up backs out the
  /// same way as a vetoed touch, and for a sturdier reason than tidiness:
  /// arming past that point would start timers nobody is left to cancel,
  /// polling a disposed recorder ten times a second until [maxDuration]
  /// runs out.
  Future<StartRecordingResult> startRecording({
    bool Function()? isStillWanted,
  }) async {
    if (_state != VoiceRecordingState.idle) {
      return StartRecordingResult.alreadyRunning;
    }

    // Voice recording is unsupported on Web in this release: the path-based
    // staging flow (`File`/`Directory`/`getTemporaryDirectory`) relies on
    // dart:io. Reported as `unsupported` (not `permissionDenied`) so the UI
    // can tell "this platform can't record" apart from "the user said no"
    // until the controller grows a MediaRecorder-backed Web variant.
    if (!PlatformSupport.supportsVoiceRecording) {
      return StartRecordingResult.unsupported;
    }

    try {
      if (!await _recorder.hasPermission()) {
        return StartRecordingResult.permissionDenied;
      }

      final dirPath = _tempDirectoryPath ?? await voiceRecorderTempPath();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$dirPath/voice_$timestamp.m4a';
      _recordingPath = path;

      if (isStillWanted != null && !isStillWanted()) {
        _recordingPath = null;
        return StartRecordingResult.aborted;
      }

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path,
      );
      if (_disposed) {
        voiceRecorderDeleteFile(path);
        return StartRecordingResult.aborted;
      }
      _captureStartedAt = DateTime.now();

      unawaited(
        voiceRecorderCleanupResidualFiles(
          dirPath,
          except: path,
          minimumAge: maxDuration + const Duration(minutes: 1),
        ),
      );

      _currentDuration = Duration.zero;
      _liveWaveform.clear();
      _isPaused = false;
      _state = VoiceRecordingState.recording;

      _startTimers();

      if (revealDelay > Duration.zero) {
        _revealTimer = Timer(revealDelay, _reveal);
      } else {
        notifyListeners();
      }
      return StartRecordingResult.started;
    } catch (_) {
      _stopTimers();
      _cleanupFile();
      _captureStartedAt = null;
      _state = VoiceRecordingState.idle;
      notifyListeners();
      return StartRecordingResult.failed;
    }
  }

  /// Notifications are held back while [_revealTimer] is pending — see
  /// [revealDelay]. Gating here rather than at each call site also covers
  /// the amplitude timer, which would otherwise reveal the recording after
  /// one sample interval.
  ///
  /// Also swallowed once disposed: stopping a capture is a chain of
  /// platform awaits, and the composer can be torn down halfway through
  /// it (the user leaves the room right after lifting the finger), which
  /// would otherwise trip the "used after being disposed" assertion.
  @override
  void notifyListeners() {
    if (_disposed) return;
    if (_revealTimer != null) return;
    super.notifyListeners();
  }

  void _reveal() {
    _revealTimer = null;
    notifyListeners();
  }

  void _endRevealDelay() {
    _revealTimer?.cancel();
    _revealTimer = null;
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
    _endRevealDelay();
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

  /// Ends a live capture and returns the message data, or null when the
  /// capture was not worth sending.
  ///
  /// [heldFor] is how long the user actually asked for it, measured from
  /// the touch that started the gesture. It is what the
  /// [minSendDuration] gate compares against, because [currentDuration]
  /// only starts counting once the platform recorder is armed and only
  /// advances in whole seconds. Callers with no gesture behind them (a
  /// locked recording being confirmed, for instance) omit it and the gate
  /// falls back to how long the recorder was up, which is honest to the
  /// millisecond.
  ///
  /// Never throws, for the same reason [startRecording] does not: every
  /// step is a platform call, and an exception escaping here would leave
  /// the controller stuck in [VoiceRecordingState.recording] with a dead
  /// microphone, a frozen composer row and an orphaned file. A failure
  /// comes back as null with [lastCaptureFailed] raised.
  ///
  /// A capture a cancellation already claimed is not one of those
  /// failures: [cancelRecording] leaves idle behind synchronously, so a
  /// release landing while it drains the platform falls out here with null
  /// and [lastCaptureFailed] untouched.
  Future<VoiceMessageData?> stopRecording({Duration? heldFor}) async {
    if (_state != VoiceRecordingState.recording) return null;
    return _finalizeRecording(heldFor: heldFor);
  }

  /// Drops the capture without sending it.
  ///
  /// The discard lands synchronously, before the first platform await, the
  /// same way [lockRecording] does and for the same reason: a slide to the
  /// left is a decision, not a request. Closing a capture takes the
  /// platform tens of milliseconds — `stop` has an MPEG-4 container to
  /// finalise — and the finger usually lifts inside that window. Were the
  /// state left standing until the platform answered, that release would
  /// find a live capture, run [stopRecording] in parallel over the same
  /// recorder and the same file, and come back empty-handed: a deliberate
  /// cancellation reported to the user as a recorder failure.
  ///
  /// Never throws either — this is the path an incoming call takes, so a
  /// platform channel returning an error (the recorder torn down by the
  /// system, a stop that blew up) must not be able to strand the composer
  /// on its recording row. Whatever the platform does, the staged file is
  /// deleted, the state goes back to idle and listeners are told.
  ///
  /// The file is the one thing that waits: it is deleted once the platform
  /// has let go of it, and by the path this call took charge of rather
  /// than by whatever the controller is staging by then, so a capture a
  /// later touch started is never deleted from under its own recorder.
  Future<void> cancelRecording() async {
    final wasPreListening = _state == VoiceRecordingState.preListen;
    final staged = _recordingPath;
    _stopTimers();
    _detachPreListenStreams();
    _recordingPath = null;
    _captureStartedAt = null;
    _state = VoiceRecordingState.idle;
    _currentDuration = Duration.zero;
    _liveWaveform.clear();
    _isPaused = false;
    try {
      if (wasPreListening) {
        await _preListenPlayer.stop();
      }
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.stop();
      }
    } catch (_) {}
    if (staged != null) voiceRecorderDeleteFile(staged);
    notifyListeners();
  }

  /// Ends the capture of a locked recording and starts previewing it.
  ///
  /// Never throws, like the rest of the cycle: the recorder and the player
  /// are both platform objects and the locked row hands this to an
  /// `onTap`, which drops the future on the floor. An exception escaping
  /// here would freeze that row — timers already stopped, state never
  /// updated, listeners never told — with the bin as the only way out and
  /// the recording lost with it. A platform that refuses leaves the
  /// preview silent instead, and the send button still works.
  Future<void> startPreListen() async {
    // If we're already in pre-listen, treat the call as "replay". Same
    // platform quirk as the message audio bubble (see `AudioBubble`):
    // calling `resume()` from `completed` state is a no-op on iOS and
    // some Android builds. Re-arm via `play(source)` which both seeks
    // to zero and starts playback. The audioplayers cache avoids
    // re-reading the file from disk.
    if (_state == VoiceRecordingState.preListen) {
      try {
        if (_recordingPath != null) {
          await _preListenPlayer.play(DeviceFileSource(_recordingPath!));
        } else {
          await _preListenPlayer.resume();
        }
      } catch (_) {}
      notifyListeners();
      return;
    }

    if (_state != VoiceRecordingState.locked) return;

    _stopTimers();
    try {
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.stop();
      }
    } catch (_) {}

    _isPaused = false;
    _state = VoiceRecordingState.preListen;

    if (_recordingPath != null) {
      _attachPreListenStreams();
      try {
        await _preListenPlayer.play(DeviceFileSource(_recordingPath!));
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Pauses the preview. Never throws, for the same reason
  /// [startPreListen] does not.
  Future<void> stopPreListen() async {
    if (_state != VoiceRecordingState.preListen) return;
    try {
      await _preListenPlayer.pause();
    } catch (_) {}
    notifyListeners();
  }

  void _attachPreListenStreams() {
    _detachPreListenStreams();
    _preListenPositionSub = _preListenPlayer.onPositionChanged.listen((pos) {
      _preListenPosition = pos;
      notifyListeners();
    });
    _preListenDurationSub = _preListenPlayer.onDurationChanged.listen((dur) {
      _preListenDuration = dur;
      notifyListeners();
    });
    _preListenStateSub = _preListenPlayer.onPlayerStateChanged.listen((
      state,
    ) async {
      _preListenPlaying = state == PlayerState.playing;
      if (state == PlayerState.completed) {
        try {
          await _preListenPlayer.seek(Duration.zero);
          _preListenPosition = Duration.zero;
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

  /// Sends what a locked recording captured, from the locked row or from
  /// the pre-listen preview.
  ///
  /// Never throws, like [stopRecording] and [cancelRecording]: the send
  /// button of the locked row drops the future on the floor, so an
  /// exception here would clamp the composer to that row with the bin —
  /// which discards the recording — as the only way out. A failure comes
  /// back as null with [lastCaptureFailed] raised.
  Future<VoiceMessageData?> confirmSend() async {
    if (_state == VoiceRecordingState.preListen) {
      _detachPreListenStreams();
      final data = await _stopPreviewAndRead();
      _lastCaptureFailed = data == null;
      _resetState();
      return data;
    }
    if (_state == VoiceRecordingState.locked) {
      return _finalizeRecording();
    }
    return null;
  }

  /// Stops the preview and reads the capture back, or returns null when
  /// the platform refused either step — the staged file being cleaned up
  /// on the way out, as it is on every other path that ends a capture.
  Future<VoiceMessageData?> _stopPreviewAndRead() async {
    try {
      await _preListenPlayer.stop();
      return await _buildVoiceMessageData();
    } catch (_) {
      _cleanupFile();
      return null;
    }
  }

  /// Stops the platform recorder and decides what the capture was worth.
  ///
  /// Two floors, not one. [minSendDuration] against `heldFor` says the
  /// user asked for a recording; [minCaptureDuration] against the span the
  /// recorder was actually up says one exists. The audio span is read
  /// before the stop round-trip so it measures the capture, not the time
  /// the platform took to close it.
  ///
  /// With no `heldFor` there is no finger to measure — a locked recording
  /// is confirmed from a button — and the first floor falls back to that
  /// same audio span. [currentDuration] would be the wrong ruler there: it
  /// only moves on whole seconds and only once the recorder is up, so a
  /// recording locked and sent within its first tick would be thrown away
  /// with a second of real audio in it.
  Future<VoiceMessageData?> _finalizeRecording({Duration? heldFor}) async {
    _stopTimers();
    _lastCaptureFailed = false;
    final capturedFor = _capturedSoFar();
    try {
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.stop();
      }

      if ((heldFor ?? capturedFor) < minSendDuration) {
        _cleanupFile();
        _resetState();
        return null;
      }

      if (capturedFor < minCaptureDuration) {
        _lastCaptureFailed = true;
        _cleanupFile();
        _resetState();
        return null;
      }

      final data = await _buildVoiceMessageData();
      if (data == null) _lastCaptureFailed = true;
      _resetState();
      return data;
    } catch (_) {
      _lastCaptureFailed = true;
      _cleanupFile();
      _resetState();
      return null;
    }
  }

  /// How long the platform recorder has been up, or zero when it never
  /// came up at all.
  Duration _capturedSoFar() {
    final startedAt = _captureStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  void _resetState() {
    _state = VoiceRecordingState.idle;
    _currentDuration = Duration.zero;
    _liveWaveform.clear();
    _isPaused = false;
    _captureStartedAt = null;
    notifyListeners();
  }

  /// Reads the staged capture back, or returns null when there is nothing
  /// worth sending in it.
  ///
  /// A file that is missing, empty, or barely bigger than an MPEG-4 header
  /// counts as nothing: a capture cut short before the encoder wrote any
  /// samples leaves exactly that behind, and shipping it would upload a
  /// silent voice message the recipient cannot play. The staged file is
  /// deleted on the way out either way.
  Future<VoiceMessageData?> _buildVoiceMessageData() async {
    if (_recordingPath == null) return null;

    final bytes = await voiceRecorderReadBytes(_recordingPath!);
    if (bytes == null || bytes.length < _kMinCaptureBytes) {
      _cleanupFile();
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
    _endRevealDelay();
  }

  void _cleanupFile() {
    if (_recordingPath != null) {
      voiceRecorderDeleteFile(_recordingPath!);
      _recordingPath = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    _detachPreListenStreams();
    _preListenPlayer.dispose();
    _recorder.dispose();
    _cleanupFile();
    super.dispose();
  }
}
