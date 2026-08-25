import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/voice_recording_controller.dart';
import '../models/voice_message_data.dart';
import '../theme/chat_theme.dart';
import '_recording_indicators.dart';

/// Tunables of the voice recorder gesture inside the composer.
///
/// The two drag numbers are matched against the cumulative offset of the
/// finger relative to where it first touched the mic button;
/// [holdHintDuration] governs the prompt shown when a touch ends without
/// producing sendable audio.
class VoiceGestureThresholds {
  const VoiceGestureThresholds({
    this.lockThreshold = -50.0,
    this.cancelThresholdRatio = 1 / 6,
    this.holdHintDuration = const Duration(milliseconds: 1600),
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

  /// How long the "hold to record" prompt stays up after a touch that
  /// produced no sendable audio. It also goes away the moment a new touch
  /// lands on the mic button, whichever comes first.
  final Duration holdHintDuration;

  double cancelThresholdFor(double screenWidth) =>
      -screenWidth * cancelThresholdRatio;
}

/// High-level state machine of the voice recorder gesture inside the
/// composer. Wraps the lower-level [VoiceRecordingController] and adds:
///
/// - cumulative drag offsets (mirrors the finger position relative to
///   the touch origin)
/// - lock / cancel threshold logic
/// - convenience getters for the composer build switch
/// - lifecycle of the recording controller (lazy create on touch down,
///   cleanup on idle / cancel / dispose)
///
/// The composer owns one of these and [VoiceRecorderGesture] feeds it the
/// raw pointer stream of the mic button; that widget also handles the
/// floating overlays (lock hint and "hold to record" prompt).
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
  bool _preparing = false;
  bool _disposed = false;
  bool _lastReleaseWasTooShort = false;
  bool _lastReleaseFailedToCapture = false;

  /// Underlying recording controller. Lazily created when the finger
  /// touches the mic button and torn down when the recorder returns to
  /// idle (or on dispose). Exposed so consumers can read live state
  /// (waveform, duration, …) — typically through a [ListenableBuilder].
  VoiceRecordingController? get recording => _recording;

  double get dragOffsetX => _dragOffsetX;
  double get dragOffsetY => _dragOffsetY;

  /// True from the instant the finger lands on the mic button until the
  /// platform recorder has resolved one way or another.
  ///
  /// Arming is not free — a permission round-trip, a temp-directory
  /// lookup and `record.start` all sit between the touch and the first
  /// captured sample. The composer paints its recording row on this flag
  /// so the touch reads as instant instead of looking dead for as long as
  /// the platform takes, and [recording] is already non-null while it is
  /// true so that row has a controller to render.
  bool get isPreparing => _preparing;

  /// Whether the last [onLongPressEnd] ended a live capture that had not
  /// been held for [VoiceRecordingController.minSendDuration].
  ///
  /// Decided once, from the same `heldFor` the controller gates the send
  /// on, so the prompt shown to the user and the decision to drop the file
  /// can never disagree. It stays false when the capture was dropped for
  /// any other reason — the user is only told to hold longer when holding
  /// longer is actually what was missing.
  bool get lastReleaseWasTooShort => _lastReleaseWasTooShort;

  /// Whether the last [onLongPressEnd] came back empty-handed because the
  /// recorder failed to deliver, not because the touch was too brief.
  ///
  /// Mirrors [VoiceRecordingController.lastCaptureFailed]. The two flags
  /// are mutually exclusive, and the composer picks a different message
  /// for each: telling someone who held the button for two seconds to
  /// hold longer is a lie, and saying nothing at all reads as the app
  /// having eaten the message.
  bool get lastReleaseFailedToCapture => _lastReleaseFailedToCapture;

  bool get isRecording => _recording?.state == VoiceRecordingState.recording;

  bool get isLocked => _recording?.state == VoiceRecordingState.locked;

  bool get isLockedOrPreListen =>
      _recording?.state == VoiceRecordingState.locked ||
      _recording?.state == VoiceRecordingState.preListen;

  /// True whenever the recorder is in any non-idle state (recording,
  /// locked, or pre-listen). The composer uses it to swap the
  /// composer/recording rows and to block a second touch from starting a
  /// recording while one is already active.
  bool get isAnyRecordingState =>
      _recording != null && _recording!.state != VoiceRecordingState.idle;

  /// Starts a fresh recording. Returns the underlying
  /// [StartRecordingResult] so the composer can surface permission
  /// errors. Idempotent: a second call while already recording returns
  /// [StartRecordingResult.alreadyRunning].
  ///
  /// [isStillWanted] is forwarded to
  /// [VoiceRecordingController.startRecording] so a touch that is already
  /// over never arms the platform recorder.
  ///
  /// Raises [isPreparing] before the first await and lowers it when the
  /// attempt resolves, notifying on both edges so the composer can show
  /// its recording row for the whole arming window. The lowering runs in a
  /// `finally`: the composer paints that row on [isPreparing], so a throw
  /// escaping the arming path would strand it on screen — recording chrome
  /// with no capture behind it and no text field to go back to.
  Future<StartRecordingResult> onLongPressStart({
    bool Function()? isStillWanted,
  }) async {
    if (_disposed) return StartRecordingResult.alreadyRunning;
    final recording = _recording ??= _recordingControllerFactory(
      maxRecordingDuration,
    );
    // Subscribed before starting rather than after: the recording
    // controller holds its `recording` notification back for a moment
    // (`revealDelay`), and this listener is what turns it into a composer
    // rebuild.
    recording.addListener(_onRecordingStateChanged);
    _preparing = true;
    notifyListeners();
    try {
      final result = await recording.startRecording(
        isStillWanted: isStillWanted,
      );
      if (result != StartRecordingResult.started) {
        recording.removeListener(_onRecordingStateChanged);
      }
      return result;
    } catch (_) {
      recording.removeListener(_onRecordingStateChanged);
      return StartRecordingResult.failed;
    } finally {
      _preparing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Handles a drag move while the finger is held down. [cumulativeOffset]
  /// is the latest position relative to the touch origin (NOT an
  /// incremental delta). [screenWidth] is
  /// used to compute the dynamic cancel threshold (1/6 of width by
  /// default), keeping accidental short drags from tearing down the
  /// recording.
  ///
  /// Only acts once capture is live. Movement produced while the recorder
  /// is still arming is not lost: [VoiceRecorderGesture] keeps the last
  /// pointer position and replays the accumulated offset here the moment
  /// the recorder reports itself started.
  ///
  /// Cancelling is fired and forgotten, but never left undecided:
  /// [VoiceRecordingController.cancelRecording] puts the recorder back to
  /// idle synchronously, before it asks the platform for anything. The
  /// finger that lifts a moment later therefore finds no live capture,
  /// stops nothing, and says nothing — the discard the user asked for is
  /// not a recorder that failed. Locking works the same way, being
  /// synchronous outright.
  void onLongPressMoveUpdate(Offset cumulativeOffset, double screenWidth) {
    if (_recording?.state != VoiceRecordingState.recording) return;

    _dragOffsetX = cumulativeOffset.dx;
    _dragOffsetY = cumulativeOffset.dy;

    final cancelThreshold = thresholds.cancelThresholdFor(screenWidth);

    if (_dragOffsetX < cancelThreshold) {
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      unawaited(_recording!.cancelRecording());
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

  /// Handles the finger lifting off. Returns the captured
  /// [VoiceMessageData] when the recording was sent successfully (i.e.
  /// long enough); null when the recording was below threshold, was in
  /// the middle of a cancel/lock transition, or was already locked
  /// (the locked recording stays alive — the composer drives confirm
  /// from the recording row instead).
  ///
  /// [heldFor] is how long the finger was down, measured from the touch
  /// itself. It gates the send (see
  /// [VoiceRecordingController.minSendDuration]) and sets
  /// [lastReleaseWasTooShort]; a capture the recorder failed to deliver
  /// sets [lastReleaseFailedToCapture] instead.
  Future<VoiceMessageData?> onLongPressEnd({Duration? heldFor}) async {
    _dragOffsetX = 0;
    _dragOffsetY = 0;
    _lastReleaseWasTooShort = false;
    _lastReleaseFailedToCapture = false;
    if (_recording == null) {
      notifyListeners();
      return null;
    }
    final recording = _recording!;
    final state = recording.state;
    if (state == VoiceRecordingState.recording) {
      _lastReleaseWasTooShort =
          heldFor != null && heldFor < VoiceRecordingController.minSendDuration;
      final data = await recording.stopRecording(heldFor: heldFor);
      _lastReleaseFailedToCapture = data == null && recording.lastCaptureFailed;
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
    if (_disposed) return;
    final controller = _recording;
    if (controller != null) {
      controller.removeListener(_onRecordingStateChanged);
    }
    _dragOffsetX = 0;
    _dragOffsetY = 0;
    _preparing = false;
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

/// Wraps the composer in the pointer listener that drives the voice
/// recorder, and owns the two floating overlays that go with it: the
/// "swipe up to lock" pill while a recording is being captured, and the
/// "hold to record" prompt after a touch too brief to produce one.
///
/// Uses a raw [Listener] rather than a [GestureDetector]: the wrapped
/// child is the whole composer, so a tap recognizer here would enter the
/// gesture arena and steal taps from the text field, the send button and
/// the attachment buttons. A [Listener] observes the pointer stream
/// without competing for it, and [voiceButtonKey] narrows the reaction
/// down to the mic button's own rectangle.
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
    this.onUnsupported,
    this.canStartRecording,
    this.onRecordingRejected,
  });

  final MessageInputVoiceController controller;
  final LayerLink layerLink;
  final ChatTheme theme;
  final VoidCallback? onPermissionDenied;
  final ValueChanged<VoiceMessageData>? onVoiceMessageReady;
  final Widget child;

  /// Called when `startRecording` reports
  /// [StartRecordingResult.unsupported] (the current platform — web in
  /// this release — cannot record voice messages at all). Falls back to
  /// [onPermissionDenied] when not supplied, so composers that haven't
  /// been updated to distinguish the two cases keep their existing
  /// behaviour.
  final VoidCallback? onUnsupported;

  /// When provided, a touch only triggers a new recording if the finger
  /// went down inside the widget identified by this key (the mic
  /// button). Outside that area the touch is ignored so taps on the text
  /// field, attach button or send button never start a recording. The
  /// drag tracking that follows once a recording is in flight is
  /// unaffected — Flutter keeps routing the pointer to this listener
  /// even when the finger leaves the mic area.
  ///
  /// The keyed widget is allowed to be there and yet have no size: the
  /// composer keeps a single mic button mounted at all times so nothing
  /// can ever hold this key twice, and shrinks it to nothing when the row
  /// on screen has no mic to offer. An empty rectangle contains no touch,
  /// which is what keeps a tap on the send button from recording.
  ///
  /// Leaving it null makes the whole child act as the mic button.
  final GlobalKey? voiceButtonKey;

  /// Asked, on every touch that lands on the mic button, whether a
  /// recording may start at all — before the recorder is armed and
  /// therefore before the platform asks for the microphone permission.
  ///
  /// A room the user cannot post to (read-only, a counterpart who cannot
  /// be messaged, a membership that ended) has no business arming the
  /// hardware for audio that can never be sent, and asking for a system
  /// permission on behalf of a message that will be refused is worse
  /// still. Returning false vetoes the touch: nothing is armed, no
  /// gesture state is taken and [onRecordingRejected] is called instead.
  ///
  /// Synchronous on purpose. An `await` here would sit between the finger
  /// landing and the recorder coming up on every legitimate recording,
  /// which is the one place in this gesture where latency is felt.
  ///
  /// Leaving it null lets every touch through, which is what composers
  /// that never had a veto keep doing.
  final bool Function()? canStartRecording;

  /// Called when [canStartRecording] vetoed a touch, so the host can say
  /// why in its own words. Falls back to a prompt floated over the mic
  /// button with [ChatUiLocalizations.recordingNotAllowed] when not
  /// supplied, so a veto is never silent.
  final VoidCallback? onRecordingRejected;

  @override
  State<VoiceRecorderGesture> createState() => _VoiceRecorderGestureState();
}

class _VoiceRecorderGestureState extends State<VoiceRecorderGesture>
    with WidgetsBindingObserver {
  OverlayEntry? _lockHintEntry;
  OverlayEntry? _holdHintEntry;
  Timer? _holdHintTimer;
  int? _activePointer;
  Offset _touchOrigin = Offset.zero;
  Offset _lastPointerPosition = Offset.zero;
  Rect _micRect = Rect.zero;
  Duration _touchDownStamp = Duration.zero;
  Duration _releaseHeldFor = Duration.zero;
  bool _startInFlight = false;
  bool _releasedBeforeStart = false;
  bool _pointerCancelled = false;

  double get _screenWidth => MediaQuery.maybeSizeOf(context)?.width ?? 360;

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
    _removeHoldHint();
    super.dispose();
  }

  /// Drops whatever the gesture had going when the app goes to the
  /// background. Mid-arming there is no capture to cancel yet, so the one
  /// on its way is vetoed instead — and marked as a cancelled pointer, the
  /// interruption being the system's and not the user failing to hold on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (widget.controller.isRecording) {
      _activePointer = null;
      unawaited(widget.controller.cancel());
      return;
    }
    if (widget.controller.isPreparing) {
      _activePointer = null;
      _releasedBeforeStart = true;
      _pointerCancelled = true;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncLockHintOverlay();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null || _startInFlight) return;
    if (widget.controller.isAnyRecordingState) return;
    final key = widget.voiceButtonKey;
    final Rect rect;
    if (key != null) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox) return;
      rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.contains(event.position)) return;
    } else {
      rect = Rect.fromCenter(center: event.position, width: 48, height: 48);
    }
    final canStart = widget.canStartRecording;
    if (canStart != null && !canStart()) {
      _micRect = rect;
      _rejectRecording();
      return;
    }
    _removeHoldHint();
    _activePointer = event.pointer;
    _touchOrigin = event.position;
    _lastPointerPosition = event.position;
    _micRect = rect;
    _touchDownStamp = event.timeStamp;
    _releaseHeldFor = Duration.zero;
    _releasedBeforeStart = false;
    _pointerCancelled = false;
    _startInFlight = true;
    unawaited(_startRecording());
  }

  /// Answers a touch the host vetoed. Nothing was armed and no gesture
  /// state was taken, so the only thing owed is an explanation: the
  /// host's own if it supplied one, the default prompt otherwise.
  void _rejectRecording() {
    final onRejected = widget.onRecordingRejected;
    if (onRejected != null) {
      _removeHoldHint();
      onRejected();
      return;
    }
    _showHintPill(widget.theme.l10nOf(context).recordingNotAllowed);
  }

  /// Arms the recorder for the touch that just landed and routes whatever
  /// comes back.
  ///
  /// The in-flight flag is cleared in a `finally` because it gates every
  /// later touch: left raised by an arming that blew up, it would kill the
  /// microphone for the rest of this widget's life.
  Future<void> _startRecording() async {
    final StartRecordingResult result;
    try {
      result = await widget.controller.onLongPressStart(
        isStillWanted: () => !_releasedBeforeStart,
      );
    } finally {
      _startInFlight = false;
    }
    if (!mounted) return;
    if (result == StartRecordingResult.aborted) {
      _releasedBeforeStart = false;
      _promptAfterUnstartedTouch();
      return;
    }
    if (result == StartRecordingResult.started) {
      if (_releasedBeforeStart) {
        // The veto lost the race: the recorder was already armed when the
        // finger lifted (an OS permission dialog, for instance, answers
        // long after the touch is over). Drop the recording instead of
        // leaving it running with no finger left to end it.
        _releasedBeforeStart = false;
        await widget.controller.cancel();
        if (mounted) _promptAfterUnstartedTouch();
        return;
      }
      _replayPendingDrag();
      return;
    }
    if (result == StartRecordingResult.failed) {
      _showRecordingFailedHint();
    } else if (result == StartRecordingResult.permissionDenied) {
      final onDenied = widget.onPermissionDenied;
      if (onDenied != null) {
        onDenied();
      } else {
        _showHintPill(widget.theme.l10nOf(context).microphonePermissionDenied);
      }
    } else if (result == StartRecordingResult.unsupported) {
      final onUnsupported = widget.onUnsupported ?? widget.onPermissionDenied;
      if (onUnsupported != null) {
        onUnsupported();
      } else {
        _showRecordingFailedHint();
      }
    }
  }

  /// Explains a touch that ended without the recorder ever coming up —
  /// but only when there is something honest to say.
  ///
  /// A pointer taken away by the system (an incoming call, a system
  /// gesture) is an interruption, not an intent to send, and a finger that
  /// travelled past the cancel threshold while the recorder was still
  /// arming asked for exactly the nothing it got. Both stay silent.
  /// Travel past the lock threshold is not a discard — it asks for the
  /// recording to carry on hands-free — so a touch that ends there with
  /// nothing behind it is owed the same explanation as any other, all the
  /// more so because on a faster device the very same flick records.
  ///
  /// What is left splits in two. A touch shorter than
  /// [VoiceRecordingController.minSendDuration] gets the "hold to record"
  /// prompt: holding longer really is what was missing. A touch that
  /// outlived it — the OS permission dialog case, where the arming
  /// resolves long after the finger is gone — did everything right and
  /// still got nothing, so it is told the recorder failed instead of
  /// being told to hold longer, which would be a lie, or being left with
  /// no message at all, which reads as the app losing the recording.
  void _promptAfterUnstartedTouch() {
    if (_pointerCancelled) return;
    final travelled = _lastPointerPosition - _touchOrigin;
    final thresholds = widget.controller.thresholds;
    if (travelled.dx < thresholds.cancelThresholdFor(_screenWidth)) return;
    if (_releaseHeldFor >= VoiceRecordingController.minSendDuration) {
      _showRecordingFailedHint();
      return;
    }
    _showHoldHint();
  }

  /// Feeds the recorder the travel the finger accumulated while the
  /// platform was still arming.
  ///
  /// Those moves reach [MessageInputVoiceController.onLongPressMoveUpdate]
  /// before capture is live and are dropped there. Flutter only emits a
  /// move when the finger actually moves, so a quick flick upwards
  /// followed by a still finger would otherwise never be re-evaluated and
  /// the recording would never lock. Replaying the cumulative offset once,
  /// the instant capture starts, closes that window.
  void _replayPendingDrag() {
    if (_activePointer == null) return;
    final offset = _lastPointerPosition - _touchOrigin;
    if (offset == Offset.zero) return;
    widget.controller.onLongPressMoveUpdate(offset, _screenWidth);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _lastPointerPosition = event.position;
    widget.controller.onLongPressMoveUpdate(
      event.position - _touchOrigin,
      _screenWidth,
    );
  }

  /// Ends the gesture, timing it on the pointer's own timeline: touch down
  /// to lift off is the span the user experiences as "how long I held it",
  /// and the only one that stays right however long the platform recorder
  /// took to come up.
  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _releaseHeldFor = event.timeStamp - _touchDownStamp;
    if (_startInFlight) {
      _releasedBeforeStart = true;
      return;
    }
    unawaited(_handleRelease());
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pointerCancelled = true;
    if (_startInFlight) {
      _releasedBeforeStart = true;
      return;
    }
    // A cancelled pointer is an interruption, not an intent to send. A
    // locked recording is left alone: it no longer depends on the finger.
    if (widget.controller.isRecording) unawaited(widget.controller.cancel());
  }

  Future<void> _handleRelease() async {
    final wasRecording = widget.controller.isRecording;
    final data = await widget.controller.onLongPressEnd(
      heldFor: _releaseHeldFor,
    );
    if (data != null) {
      widget.onVoiceMessageReady?.call(data);
      return;
    }
    if (!mounted || !wasRecording) return;
    if (widget.controller.lastReleaseWasTooShort) {
      _showHoldHint();
    } else if (widget.controller.lastReleaseFailedToCapture) {
      _showRecordingFailedHint();
    }
  }

  /// Tells the user to hold the button longer. Only ever for a touch that
  /// really was too brief — see [_promptAfterUnstartedTouch].
  void _showHoldHint() =>
      _showHintPill(widget.theme.l10nOf(context).holdToRecord);

  /// Reports a recorder that did not deliver: the platform refused to arm
  /// it, the capture never went live, or it came back with no audio in
  /// it. Distinct from [_showHoldHint] on purpose — the user did their
  /// part in every one of those cases.
  void _showRecordingFailedHint() =>
      _showHintPill(widget.theme.l10nOf(context).recordingFailed);

  /// Floats a transient prompt above the mic button.
  ///
  /// Anchored on the button rectangle captured at touch down rather than
  /// on [VoiceRecorderGesture.layerLink]: the prompt outlives the gesture,
  /// and the composer may well have moved on to a row that gives the mic
  /// button no size at all (the send button takes its place as soon as
  /// there is text), which would leave a follower with nothing to sit on.
  /// An empty string suppresses it entirely, which is how a host silences
  /// either message.
  void _showHintPill(String text) {
    if (text.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _removeHoldHint();
    final anchor = _micRect;
    _holdHintEntry = OverlayEntry(
      builder: (overlayContext) {
        final gap = MediaQuery.sizeOf(overlayContext).height - anchor.top + 12;
        return Positioned(
          left: 16,
          right: 16,
          bottom: gap > 0 ? gap : 0.0,
          child: Align(
            child: Material(
              color: Colors.transparent,
              child: HoldToRecordHintPill(theme: widget.theme, text: text),
            ),
          ),
        );
      },
    );
    overlay.insert(_holdHintEntry!);
    _holdHintTimer = Timer(
      widget.controller.thresholds.holdHintDuration,
      _removeHoldHint,
    );
  }

  void _removeHoldHint() {
    _holdHintTimer?.cancel();
    _holdHintTimer = null;
    _holdHintEntry
      ?..remove()
      ..dispose();
    _holdHintEntry = null;
  }

  void _syncLockHintOverlay() {
    final shouldShow =
        widget.controller.isRecording || widget.controller.isPreparing;
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
    _lockHintEntry
      ?..remove()
      ..dispose();
    _lockHintEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      // Opaque so the whole mic button rectangle reacts, not just the
      // painted glyph inside it. Children are still hit-tested first and
      // ancestors still receive the pointer, so nothing is stolen.
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
