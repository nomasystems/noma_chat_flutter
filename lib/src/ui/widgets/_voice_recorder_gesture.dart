import 'package:flutter/material.dart';

import '../controller/voice_recording_controller.dart';
import '../models/voice_message_data.dart';
import '../theme/chat_theme.dart';
import '_recording_indicators.dart';

/// Drag thresholds for the slide-to-cancel / slide-to-lock gesture
/// inside the composer. Matched against the long-press
/// `localOffsetFromOrigin` cumulative offset.
class VoiceGestureThresholds {
  const VoiceGestureThresholds({
    this.lockThreshold = -50.0,
    this.cancelThresholdRatio = 1 / 6,
  });

  /// Vertical offset (negative px) past which the recording locks.
  /// 50px — half the previous 100px. Recording locks earlier so the
  /// "slide-up to lock" gesture matches the muscle memory of a short
  /// upward flick instead of a deliberate half-thumb travel.
  final double lockThreshold;

  /// Fraction of the screen width past which a leftward drag cancels
  /// the recording. 1/6 — half the previous 1/3. Cancel triggers
  /// earlier so the user doesn't have to slide the finger nearly
  /// across the screen, while still requiring a deliberate slide
  /// (a typical accidental drag is under ~30px).
  final double cancelThresholdRatio;

  double cancelThresholdFor(double screenWidth) =>
      -screenWidth * cancelThresholdRatio;
}

/// High-level state machine of the voice recorder gesture inside the
/// composer. Wraps the lower-level [VoiceRecordingController] and adds:
///
/// - cumulative drag offsets (mirrors the finger position relative to
///   the long-press origin)
/// - lock / cancel threshold logic
/// - convenience getters for the composer build switch
/// - lifecycle of the recording controller (lazy create on long-press,
///   cleanup on idle / cancel / dispose)
///
/// The composer owns one of these and forwards `onLongPress*` callbacks
/// from a [GestureDetector]; the embedded [_VoiceRecorderGesture] widget
/// then handles the lock-hint overlay.
class MessageInputVoiceController extends ChangeNotifier {
  MessageInputVoiceController({
    required this.maxRecordingDuration,
    this.thresholds = const VoiceGestureThresholds(),
    VoiceRecordingControllerFactory? recordingControllerFactory,
  }) : _recordingControllerFactory =
           recordingControllerFactory ??
           ((max) => VoiceRecordingController(maxDuration: max));

  final Duration maxRecordingDuration;
  final VoiceGestureThresholds thresholds;
  final VoiceRecordingControllerFactory _recordingControllerFactory;

  VoiceRecordingController? _recording;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;
  bool _disposed = false;

  /// Underlying recording controller. Lazily created when the user
  /// initiates a long-press and torn down when the recorder returns to
  /// idle (or on dispose). Exposed so consumers can read live state
  /// (waveform, duration, …) — typically through a [ListenableBuilder].
  VoiceRecordingController? get recording => _recording;

  double get dragOffsetX => _dragOffsetX;
  double get dragOffsetY => _dragOffsetY;

  bool get isRecording => _recording?.state == VoiceRecordingState.recording;

  bool get isLocked => _recording?.state == VoiceRecordingState.locked;

  bool get isLockedOrPreListen =>
      _recording?.state == VoiceRecordingState.locked ||
      _recording?.state == VoiceRecordingState.preListen;

  /// True whenever the recorder is in any non-idle state (recording,
  /// locked, or pre-listen). The composer uses it to swap the
  /// composer/recording rows and to block accidental long-presses while
  /// a recording is already active.
  bool get isAnyRecordingState =>
      _recording != null && _recording!.state != VoiceRecordingState.idle;

  /// Starts a fresh recording. Returns the underlying
  /// [StartRecordingResult] so the composer can surface permission
  /// errors. Idempotent: a second call while already recording returns
  /// [StartRecordingResult.alreadyRunning].
  Future<StartRecordingResult> onLongPressStart() async {
    if (_disposed) return StartRecordingResult.alreadyRunning;
    _recording ??= _recordingControllerFactory(maxRecordingDuration);
    final result = await _recording!.startRecording();
    if (result == StartRecordingResult.started) {
      _recording!.addListener(_onRecordingStateChanged);
      notifyListeners();
    }
    return result;
  }

  /// Handles a drag move while the long-press is held. [cumulativeOffset]
  /// is the latest absolute position relative to the long-press origin
  /// (NOT an incremental delta) — matches
  /// `LongPressMoveUpdateDetails.localOffsetFromOrigin`. [screenWidth] is
  /// used to compute the dynamic cancel threshold (1/3 of width by
  /// default), keeping accidental short drags from tearing down the
  /// recording.
  void onLongPressMoveUpdate(Offset cumulativeOffset, double screenWidth) {
    if (_recording?.state != VoiceRecordingState.recording) return;

    _dragOffsetX = cumulativeOffset.dx;
    _dragOffsetY = cumulativeOffset.dy;

    final cancelThreshold = thresholds.cancelThresholdFor(screenWidth);

    if (_dragOffsetX < cancelThreshold) {
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _recording!.cancelRecording();
      notifyListeners();
      return;
    }
    if (_dragOffsetY < thresholds.lockThreshold) {
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _recording!.lockRecording();
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  /// Handles long-press release. Returns the captured
  /// [VoiceMessageData] when the recording was sent successfully (i.e.
  /// long enough); null when the recording was below threshold, was in
  /// the middle of a cancel/lock transition, or was already locked
  /// (the locked recording stays alive — the composer drives confirm
  /// from the recording row instead).
  Future<VoiceMessageData?> onLongPressEnd() async {
    _dragOffsetX = 0;
    _dragOffsetY = 0;
    if (_recording == null) {
      notifyListeners();
      return null;
    }
    final state = _recording!.state;
    if (state == VoiceRecordingState.recording) {
      final data = await _recording!.stopRecording();
      _cleanup();
      return data;
    }
    notifyListeners();
    return null;
  }

  /// Confirms a locked / pre-listen send. Returns the recorded data on
  /// success and clears the controller.
  Future<VoiceMessageData?> confirmSend() async {
    final controller = _recording;
    if (controller == null) return null;
    final state = controller.state;
    VoiceMessageData? data;
    if (state == VoiceRecordingState.recording) {
      data = await controller.stopRecording();
    } else if (state == VoiceRecordingState.locked ||
        state == VoiceRecordingState.preListen) {
      data = await controller.confirmSend();
    }
    _cleanup();
    return data;
  }

  /// Cancels the active recording (if any) without sending.
  Future<void> cancel() async {
    final controller = _recording;
    if (controller == null) return;
    await controller.cancelRecording();
    _cleanup();
  }

  void _onRecordingStateChanged() {
    if (_disposed) return;
    if (_recording?.state == VoiceRecordingState.idle) {
      _cleanup();
    } else {
      notifyListeners();
    }
  }

  void _cleanup() {
    final controller = _recording;
    if (controller != null) {
      controller.removeListener(_onRecordingStateChanged);
    }
    _dragOffsetX = 0;
    _dragOffsetY = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _recording;
    if (controller != null) {
      controller.removeListener(_onRecordingStateChanged);
      controller.dispose();
      _recording = null;
    }
    super.dispose();
  }
}

/// Factory used by [MessageInputVoiceController] to build the underlying
/// [VoiceRecordingController]. Replaceable in tests.
typedef VoiceRecordingControllerFactory =
    VoiceRecordingController Function(Duration maxDuration);

/// Wraps the composer in the long-press gesture detector that drives
/// the voice recorder, and renders the floating "swipe up to lock"
/// overlay pill while a recording is active.
///
/// Owns no recording state itself — everything flows through the
/// [MessageInputVoiceController] passed in. Held as a [StatefulWidget]
/// because the lock-hint [OverlayEntry] has imperative lifecycle that
/// must follow `mounted` / `widget.controller` changes.
class VoiceRecorderGesture extends StatefulWidget {
  const VoiceRecorderGesture({
    super.key,
    required this.controller,
    required this.layerLink,
    required this.theme,
    required this.onPermissionDenied,
    required this.onVoiceMessageReady,
    required this.child,
    this.voiceButtonKey,
  });

  final MessageInputVoiceController controller;
  final LayerLink layerLink;
  final ChatTheme theme;
  final VoidCallback? onPermissionDenied;
  final ValueChanged<VoiceMessageData>? onVoiceMessageReady;
  final Widget child;

  /// When provided, long-press only triggers a new recording if the
  /// finger went down inside the widget identified by this key (the mic
  /// button). Outside that area the gesture is ignored so accidental
  /// long-presses on the text field, attach button or send button never
  /// start a recording. The drag tracking that follows once a recording
  /// is in flight is unaffected — Flutter keeps the gesture latched to
  /// the original touch even when the finger leaves the mic area.
  final GlobalKey? voiceButtonKey;

  @override
  State<VoiceRecorderGesture> createState() => _VoiceRecorderGestureState();
}

class _VoiceRecorderGestureState extends State<VoiceRecorderGesture>
    with WidgetsBindingObserver {
  OverlayEntry? _lockHintEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant VoiceRecorderGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _removeLockHintOverlay();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.controller.isRecording) {
      widget.controller.cancel();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncLockHintOverlay();
  }

  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    final key = widget.voiceButtonKey;
    if (key != null) {
      final ctx = key.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox) return;
      final origin = box.localToGlobal(Offset.zero);
      final rect = origin & box.size;
      if (!rect.contains(details.globalPosition)) return;
    }
    final result = await widget.controller.onLongPressStart();
    if (!mounted) return;
    if (result == StartRecordingResult.permissionDenied) {
      widget.onPermissionDenied?.call();
    }
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 360;
    widget.controller.onLongPressMoveUpdate(
      details.localOffsetFromOrigin,
      screenWidth,
    );
  }

  Future<void> _handleLongPressEnd() async {
    final data = await widget.controller.onLongPressEnd();
    if (data != null) widget.onVoiceMessageReady?.call(data);
  }

  void _syncLockHintOverlay() {
    final shouldShow = widget.controller.isRecording;
    if (shouldShow && _lockHintEntry == null) {
      _showLockHintOverlay();
    } else if (!shouldShow && _lockHintEntry != null) {
      _removeLockHintOverlay();
    }
  }

  void _showLockHintOverlay() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _lockHintEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: widget.layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -12),
            child: Material(
              color: Colors.transparent,
              child:
                  widget.theme.input.lockHintBuilder?.call(overlayContext) ??
                  LockHintPill(theme: widget.theme),
            ),
          ),
        );
      },
    );
    overlay.insert(_lockHintEntry!);
  }

  void _removeLockHintOverlay() {
    _lockHintEntry?.remove();
    _lockHintEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final isRecordingNow = widget.controller.isAnyRecordingState;
    return GestureDetector(
      onLongPressStart: !isRecordingNow ? _handleLongPressStart : null,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: (_) => _handleLongPressEnd(),
      behavior: isRecordingNow
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      child: widget.child,
    );
  }
}
