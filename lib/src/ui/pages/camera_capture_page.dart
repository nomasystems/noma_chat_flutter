import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../_internal/ui_debug_log.dart';
import '../l10n/chat_ui_localizations.dart';
import '../models/camera_capture_result.dart';
import '../room_defaults.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../utils/chat_notice.dart';
import '../utils/platform_support.dart';
import 'camera_capture_review.dart';
import 'camera_recording_gate.dart';

/// Full-screen in-app camera: tap the shutter for a still, hold it to
/// record a clip. Pops with a [CameraCaptureResult], or `null` when the
/// user backs out.
///
/// The shutter never sends. Whatever it produces lands on an in-flow
/// review step ([CameraCaptureReview]) showing the still full-screen or
/// the clip playable, and only its Send button pops the capture back to
/// the caller; Retake returns to the viewfinder and Discard leaves with
/// nothing. Captures the user did not confirm are deleted here, since
/// nobody downstream ever learns they existed.
///
/// This is the SDK's own capture screen, not `image_picker`'s system
/// camera — it is what makes "hold to record" possible at all, and it
/// keeps the capture inside the app so the composer never loses focus.
/// [PlatformSupport.supportsInAppCameraCapture] gates it.
///
/// Push it with [show], or mount it yourself (it is a plain widget, with
/// no routing package baked in). `NomaChatView` already opens it from the
/// attachment sheet's Camera row and sends what comes back; wire
/// `ChatViewCallbacks.onPickCamera` to replace that flow entirely.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.theme = ChatTheme.defaults,
    this.videoPreviewBuilder,
  });

  final ChatTheme theme;

  /// Replaces the review step's clip preview. `null` plays the capture
  /// with `video_player` through [CameraVideoPreview]. Never consulted for
  /// a still.
  final CameraVideoPreviewBuilder? videoPreviewBuilder;

  /// Pushes the capture screen and returns what the user confirmed on the
  /// review step, or `null` when nothing was confirmed — a discard, a
  /// cancellation, or a platform without an in-app camera.
  static Future<CameraCaptureResult?> show({
    required BuildContext context,
    ChatTheme theme = ChatTheme.defaults,
    bool fullscreenDialog = true,
    CameraVideoPreviewBuilder? videoPreviewBuilder,
  }) {
    if (!PlatformSupport.supportsInAppCameraCapture) {
      return Future<CameraCaptureResult?>.value();
    }
    return Navigator.of(context).push<CameraCaptureResult>(
      MaterialPageRoute<CameraCaptureResult>(
        fullscreenDialog: fullscreenDialog,
        builder: (_) => CameraCapturePage(
          theme: theme,
          videoPreviewBuilder: videoPreviewBuilder,
        ),
      ),
    );
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver, ChatNoticeAnchor<CameraCapturePage> {
  @override
  ChatTheme get noticeTheme => widget.theme;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _activeCameraIndex = 0;
  final _recordingGate = CameraRecordingGate();
  bool _initializing = true;
  String? _error;
  // Whether the error above stems from a permission the system will not
  // prompt for again, in which case the only way out is the Settings app.
  bool _showSettingsCta = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;
  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _requestingMicrophone = false;
  bool _binding = false;
  bool _holdActive = false;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double? _requestedZoom;
  bool _applyingZoom = false;
  // Handed over by [dispose] when the screen goes away with a start still in
  // flight: the resolving `_startRecording` is the only place left that can
  // finalise the clip, and it needs a controller to do it on.
  CameraController? _orphanedController;
  // Kept apart from [_error]: rebinding the preview clears the error, and the
  // user still has to learn that the clip they were recording is gone.
  String? _interruptionNotice;
  // The capture waiting on the review step. While it is set the viewfinder
  // is off-screen and no gesture on this page can send anything — only the
  // review's own Send button pops.
  CameraCaptureResult? _pendingCapture;
  // Whether [_pendingCapture] has been handed to the caller. Everything
  // else — a discard, a host popping this route, a teardown — leaves a file
  // in the app cache that only [dispose] is left to collect.
  bool _captureConfirmed = false;

  ChatUiLocalizations get _l10n => noticeL10n;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    final pending = _pendingCapture;
    _pendingCapture = null;
    if (pending != null && !_captureConfirmed) {
      // The screen is leaving with a take nobody accepted — a discard, or a
      // host popping this route out from under the review.
      unawaited(_deleteCapture(pending));
    }
    final controller = _controller;
    _controller = null;
    if (_recordingGate.isStarting) {
      _orphanedController = controller;
    } else {
      unawaited(
        _releaseController(
          controller,
          // A controller disposed mid-recording aborts the clip the platform
          // is still writing; only its stop call closes the file.
          finalizeRecording:
              _recordingGate.isRecording || _recordingGate.isStopping,
        ),
      );
    }
    super.dispose();
  }

  /// Finalises and releases a controller nobody is watching any more.
  Future<void> _releaseController(
    CameraController? controller, {
    required bool finalizeRecording,
  }) async {
    if (controller == null) return;
    if (finalizeRecording) {
      try {
        await controller.stopVideoRecording();
      } on Object catch (error, stack) {
        uiDebugLog(
          'CameraCapturePage',
          'stop on teardown failed: $error\n$stack',
        );
      }
    }
    _recordingGate.completeStop();
    await _disposeQuietly(controller);
  }

  /// Releases the controller [dispose] handed over, if it did.
  Future<void> _releaseOrphan({required bool finalizeRecording}) async {
    final controller = _orphanedController;
    _orphanedController = null;
    if (controller == null) {
      _recordingGate.completeStop();
      return;
    }
    await _releaseController(controller, finalizeRecording: finalizeRecording);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final interrupted = _recordingGate.interruptIfActive();
      _controller = null;
      unawaited(controller.dispose());
      if (!mounted) return;
      setState(() {
        _recordingElapsed = Duration.zero;
        if (interrupted) {
          _interruptionNotice = _l10n.cameraUnavailable;
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_requestingMicrophone || _controller != null) return;
      // Covers both a lifecycle teardown with the permission still fine and
      // the dead-end permission error: only a real status check tells them
      // apart, since `_cameraGranted` is otherwise never refreshed after a
      // trip to the Settings app.
      unawaited(_recheckCameraPermission());
    }
  }

  Future<void> _setup() async {
    final PermissionStatus cameraStatus;
    try {
      cameraStatus = await Permission.camera.request();
      // Read-only: a still photo does not need audio, so the microphone prompt
      // is deferred to the first hold-to-record gesture.
      _microphoneGranted = await Permission.microphone.isGranted;
    } on Object catch (error, stack) {
      // `permission_handler` refuses to queue behind another plugin's dialog
      // (ERROR_ALREADY_REQUESTING_PERMISSIONS). Left unhandled that is a
      // spinner that never resolves, because nothing else clears
      // `_initializing`.
      _failToOpen('camera permission request failed', error, stack);
      return;
    }
    await _applyCameraPermissionStatus(cameraStatus);
  }

  Future<void> _recheckCameraPermission() async {
    final PermissionStatus status;
    try {
      status = await Permission.camera.status;
    } on Object catch (error, stack) {
      _failToOpen('camera permission check failed', error, stack);
      return;
    }
    await _applyCameraPermissionStatus(status);
  }

  void _failToOpen(String what, Object error, StackTrace stack) {
    uiDebugLog('CameraCapturePage', '$what: $error\n$stack');
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _error = _l10n.cameraUnavailable;
      _showSettingsCta = false;
    });
  }

  Future<void> _applyCameraPermissionStatus(PermissionStatus status) async {
    _cameraGranted = status.isGranted;
    if (!_cameraGranted) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _l10n.cameraPermissionDenied;
        _showSettingsCta = status.isPermanentlyDenied || status.isRestricted;
      });
      return;
    }
    _showSettingsCta = false;
    await _bindCameraAfterPermissions();
  }

  /// `_binding` gates the shutter and the flip button in [build], so it can
  /// only move inside a rebuild — the bind's own `setState` runs while it is
  /// still `true` and never publishes the release.
  void _setBinding(bool value) {
    if (_binding == value) return;
    if (!mounted) {
      _binding = value;
      return;
    }
    setState(() => _binding = value);
  }

  Future<void> _bindCameraAfterPermissions() async {
    if (!_cameraGranted || _binding) return;
    _setBinding(true);
    try {
      if (_cameras.isEmpty) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          if (!mounted) return;
          setState(() {
            _initializing = false;
            _error = _l10n.cameraUnavailable;
          });
          return;
        }
        _cameras = cameras;
      }
      await _bindCamera(_activeCameraIndex);
    } on Exception catch (error, stack) {
      uiDebugLog('CameraCapturePage', 'bind failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _l10n.cameraUnavailable;
      });
    } finally {
      _setBinding(false);
    }
  }

  Future<void> _bindCamera(int index) async {
    // Both plugins ask for the microphone while *creating* the camera when
    // audio is on (iOS `CameraPlugin.create`, Android
    // `CameraPermissionsManager.requestPermissions`), and on iOS a previously
    // denied microphone makes that create call fail outright, killing the
    // preview. Audio stays off until the permission is actually held.
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: _microphoneGranted,
    );
    try {
      await controller.initialize();
    } on Exception catch (error, stack) {
      uiDebugLog('CameraCapturePage', 'initialize failed: $error\n$stack');
      // `initialize` opens the native session before the step that failed, so
      // the half-built candidate is ours to release — nothing else holds a
      // reference to it once we rethrow.
      await _disposeQuietly(controller);
      rethrow;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // The zoom range is per-lens (the front camera rarely matches the back
    // one), so it is re-read on every bind rather than cached across them.
    var minZoom = 1.0;
    var maxZoom = 1.0;
    try {
      minZoom = await controller.getMinZoomLevel();
      maxZoom = await controller.getMaxZoomLevel();
    } on Exception catch (error, stack) {
      uiDebugLog('CameraCapturePage', 'zoom range unreadable: $error\n$stack');
      // A lens that rejects the query just keeps the pinch gesture inert.
      // Both ends go back to the seed together: a half-read range would leave
      // the minimum above the maximum and make the pinch clamp throw.
      minZoom = 1.0;
      maxZoom = 1.0;
    }
    if (maxZoom < minZoom) {
      minZoom = 1.0;
      maxZoom = 1.0;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    final previous = _controller;
    setState(() {
      _controller = controller;
      _activeCameraIndex = index;
      _initializing = false;
      _error = null;
      _showSettingsCta = false;
      _minZoom = minZoom;
      _maxZoom = maxZoom;
      _currentZoom = minZoom;
      _requestedZoom = null;
    });
    await _disposeQuietly(previous);
  }

  /// Releases a controller we are done with. Never throws: the native session
  /// is routinely closed already by the time we get here, and letting that
  /// surface would be read as "the camera we just opened failed" and tear the
  /// working preview back down.
  Future<void> _disposeQuietly(CameraController? controller) async {
    try {
      await controller?.dispose();
    } on Exception catch (error, stack) {
      // Nothing to salvage: the session is gone either way.
      uiDebugLog('CameraCapturePage', 'dispose failed: $error\n$stack');
    }
  }

  bool get _canSwitchCamera =>
      _cameras.length > 1 &&
      !_recordingGate.isRecording &&
      !_recordingGate.isStarting &&
      !_recordingGate.isStopping &&
      !_binding &&
      !_initializing;

  Future<void> _switchCamera() async {
    if (!_canSwitchCamera) return;
    final previousIndex = _activeCameraIndex;
    final next = (previousIndex + 1) % _cameras.length;
    final outgoing = _controller;
    setState(() {
      _binding = true;
      _controller = null;
      _initializing = true;
      _interruptionNotice = null;
    });
    await _disposeQuietly(outgoing);
    try {
      await _bindCamera(next);
    } on Exception catch (error, stack) {
      uiDebugLog('CameraCapturePage', 'lens switch failed: $error\n$stack');
      await _recoverPreviousCamera(previousIndex);
    } finally {
      _setBinding(false);
    }
  }

  Future<void> _recoverPreviousCamera(int previousIndex) async {
    final stale = _controller;
    _controller = null;
    await _disposeQuietly(stale);
    if (!mounted) return;
    try {
      await _bindCamera(previousIndex);
    } on Exception catch (error, stack) {
      uiDebugLog('CameraCapturePage', 'lens recovery failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _l10n.cameraUnavailable;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _interruptionNotice = _l10n.cameraUnavailable;
    });
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isTakingPicture) return;
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      _presentForReview(CameraCaptureResult(file: file, isVideo: false));
    } on Object catch (error, stack) {
      // Not just `Exception`: `takePicture` signs off by writing to the
      // controller's value, so a teardown landing mid-capture raises a
      // `FlutterError` instead.
      uiDebugLog('CameraCapturePage', 'takePicture failed: $error\n$stack');
      if (!mounted || _controller != controller) return;
      setState(() => _error = _l10n.cameraUnavailable);
    }
  }

  Future<void> _startRecording() async {
    _holdActive = true;
    var controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_microphoneGranted) {
      if (!await _ensureMicrophone()) return;
      controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
    }
    final attempt = _recordingGate.beginStart();
    if (attempt == null) return;
    // The gate is read by `build` through `_canSwitchCamera`, so arming it
    // has to publish a frame: otherwise the flip button stays enabled for
    // the whole start-in-flight window and can dispose the controller
    // `startVideoRecording` is about to write to.
    if (mounted) setState(() {});
    try {
      await controller.startVideoRecording();
    } on Object catch (error, stack) {
      // Not just `Exception`: a teardown that lands mid-start disposes the
      // controller, and `startVideoRecording` signs off by writing to it,
      // which fails an assertion rather than throwing. Either way there is no
      // recording, and a retired attempt has nobody left to report to.
      uiDebugLog(
        'CameraCapturePage',
        'startVideoRecording failed: $error\n$stack',
      );
      unawaited(_releaseOrphan(finalizeRecording: false));
      if (_recordingGate.isStale(attempt)) return;
      _recordingGate.reset();
      if (!mounted) return;
      setState(() {
        _error = _l10n.cameraUnavailable;
      });
      return;
    }
    final outcome = _recordingGate.completeStart(attempt);
    // An interruption (incoming call, lens switch) can retire the gate while
    // `startVideoRecording` is in flight; re-arming it here would leave the
    // timer and the red pill running against a controller that is already
    // disposed, with no gesture left that can clear them.
    if (outcome == CameraStartOutcome.stale) {
      unawaited(_releaseOrphan(finalizeRecording: true));
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    // The finger may have already lifted while `startVideoRecording` was
    // in flight: that release already asked to stop, so we honour it
    // immediately instead of showing the recording UI for a gesture the
    // user already ended.
    if (outcome == CameraStartOutcome.stopImmediately) {
      unawaited(_stopRecording());
      return;
    }
    if (!mounted) {
      // The screen went away while the start was in flight: the platform is
      // recording with nobody left to release the shutter, and simply
      // dropping the controller aborts the clip instead of closing the file.
      _recordingGate.requestStop();
      unawaited(_releaseOrphan(finalizeRecording: true));
      return;
    }
    setState(() {
      _recordingElapsed = Duration.zero;
      _interruptionNotice = null;
    });
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _recordingElapsed += const Duration(seconds: 1)),
    );
  }

  /// Prompts for the microphone on the first hold-to-record gesture and
  /// rebinds the camera with audio. Returns `false` when recording must not
  /// proceed; photo capture stays available either way.
  Future<bool> _ensureMicrophone() async {
    _requestingMicrophone = true;
    PermissionStatus status;
    try {
      status = await Permission.microphone.request();
    } on Object catch (error, stack) {
      // A refused dialog and a dialog that could not be raised at all (another
      // plugin's request already in flight) are the same thing here: no audio.
      // Left to escape, this throw would surface as an unhandled async error
      // from a gesture callback nobody awaits.
      uiDebugLog(
        'CameraCapturePage',
        'microphone permission request failed: $error\n$stack',
      );
      status = PermissionStatus.denied;
    } finally {
      _requestingMicrophone = false;
    }
    _microphoneGranted = status.isGranted;
    if (!mounted) return false;
    // The system prompt sends the app through `inactive`, which tears the
    // preview down; rebind on both outcomes so photos keep working.
    final controller = _controller;
    if (controller == null || controller.enableAudio != _microphoneGranted) {
      await _bindCameraAfterPermissions();
    }
    if (!mounted) return false;
    if (!_microphoneGranted) {
      final permanentlyBlocked =
          status.isPermanentlyDenied || status.isRestricted;
      final l10n = _l10n;
      showNotice(
        l10n.microphonePermissionDenied,
        snackBarBuilder: (context, message) => SnackBar(
          content: Text(message),
          // Cleared of the shutter, which owns the bottom strip of the screen.
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: _shutterSize + 66,
          ),
          action: permanentlyBlocked
              ? SnackBarAction(
                  label: l10n.openSettings,
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
      return false;
    }
    // Answering the prompt cancels the touch, and a `PointerCancelEvent` never
    // produces an `onLongPressEnd` — `_cancelHold` is what clears the flag, so
    // only a hold that survived the dialog rolls straight into recording.
    return _holdActive;
  }

  /// The gesture was torn down without a release (a permission dialog or any
  /// other pointer cancellation). Treated as a release so no recording is left
  /// running with nobody's finger on the shutter.
  void _cancelHold() {
    _holdActive = false;
    if (_recordingGate.isStarting || _recordingGate.isRecording) {
      unawaited(_stopRecording());
    }
  }

  Future<void> _stopRecording() async {
    _holdActive = false;
    // The gate is cleared before the controller is even looked at: a release
    // that arrives once the camera is gone still has to disarm the recording
    // UI, which used to survive the teardown with no way left to stop it.
    final session = _recordingGate.currentSession;
    if (!_recordingGate.requestStop()) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      unawaited(_releaseOrphan(finalizeRecording: true));
      if (!mounted) return;
      setState(() => _recordingElapsed = Duration.zero);
      return;
    }
    try {
      final file = await controller.stopVideoRecording();
      _recordingGate.completeStop();
      // An interruption that landed inside the round-trip already told the
      // user the clip was lost and rebound the preview behind it.
      if (_recordingGate.isStale(session) || !mounted) return;
      setState(() => _recordingElapsed = Duration.zero);
      _presentForReview(CameraCaptureResult(file: file, isVideo: true));
    } on Object catch (error, stack) {
      // Not just `Exception`: `stopVideoRecording` signs off by writing to the
      // controller's value, which raises a `FlutterError` once a teardown has
      // disposed it.
      uiDebugLog(
        'CameraCapturePage',
        'stopVideoRecording failed: $error\n$stack',
      );
      if (_recordingGate.isStale(session)) return;
      _recordingGate.reset();
      if (!mounted) return;
      setState(() {
        _recordingElapsed = Duration.zero;
        _error = _l10n.cameraUnavailable;
      });
    }
  }

  /// Puts a fresh capture on the review step. The camera stays bound
  /// behind it so Retake is instant instead of a second cold start.
  void _presentForReview(CameraCaptureResult capture) {
    setState(() {
      _pendingCapture = capture;
      _interruptionNotice = null;
    });
  }

  /// Confirms the capture: the one path on this screen that sends.
  ///
  /// The pending capture is deliberately left in place across the pop, so
  /// the review — not a viewfinder nobody asked for — is what stays on
  /// screen through the exit transition. [_captureConfirmed] is what stops
  /// [dispose] from deleting the file the caller now owns.
  void _sendPendingCapture() {
    final capture = _pendingCapture;
    if (capture == null) return;
    _captureConfirmed = true;
    Navigator.of(context).pop(capture);
  }

  /// Throws the take away and goes back to the live preview. The one exit
  /// that keeps the screen alive, so it collects the file itself.
  void _retakePendingCapture() {
    final capture = _pendingCapture;
    if (capture == null) return;
    setState(() => _pendingCapture = null);
    unawaited(_deleteCapture(capture));
  }

  /// Leaves the camera without sending, exactly like the viewfinder's own
  /// close button. [dispose] collects the file on the way out.
  void _discardPendingCapture() {
    if (_pendingCapture == null) return;
    Navigator.of(context).pop();
  }

  /// Removes a capture nobody will ever ask for. The camera plugins write
  /// into the app cache and nothing else collects it, so an unconfirmed
  /// take would otherwise sit there at full size until the OS reclaims it.
  Future<void> _deleteCapture(CameraCaptureResult capture) async {
    try {
      await File(capture.file.path).delete();
    } on Object catch (error) {
      // Routine: a test double or a platform that already moved the file.
      uiDebugLog('CameraCapturePage', 'could not delete capture: $error');
    }
  }

  String _formatElapsed(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Color get _foreground =>
      widget.theme.cameraCaptureForegroundColor ??
      DefaultPalette.cameraCaptureForeground;

  Color get _recordingColor =>
      widget.theme.cameraCaptureRecordingColor ??
      DefaultPalette.cameraCaptureRecording;

  double get _shutterSize =>
      widget.theme.cameraCaptureShutterSize ?? RoomDefaults.cameraShutterSize;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor:
          theme.cameraCaptureBackgroundColor ??
          DefaultPalette.cameraCaptureBackground,
      body: SafeArea(
        child: _pendingCapture == null ? _buildViewfinder() : _buildReview(),
      ),
    );
  }

  /// The review step, plus the back-gesture contract that goes with it: on
  /// this screen "back" means "shoot again", not "leave with the take
  /// silently dropped on the floor".
  Widget _buildReview() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _retakePendingCapture();
      },
      child: CameraCaptureReview(
        result: _pendingCapture!,
        theme: widget.theme,
        videoPreviewBuilder: widget.videoPreviewBuilder,
        onSend: _sendPendingCapture,
        onRetake: _retakePendingCapture,
        onDiscard: _discardPendingCapture,
      ),
    );
  }

  Widget _buildViewfinder() {
    final theme = widget.theme;
    final l10n = _l10n;
    final foreground = _foreground;
    // Every slot is keyed and unconditional. A `Stack` matches children by
    // position, so an overlay that comes and goes (the recording pill) used
    // to shift the shutter one place down the list and rebuild its
    // `GestureDetector` from scratch — mid-press, on any device with a
    // single lens, which loses the release that ends the clip.
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(
          key: const ValueKey('chat_camera_preview'),
          child: Semantics(
            identifier: 'chat_camera_preview',
            child: _buildPreview(),
          ),
        ),
        Positioned(
          key: const ValueKey('chat_camera_close'),
          top: 8,
          left: 8,
          child: Semantics(
            identifier: 'chat_camera_close',
            button: true,
            label: l10n.close,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: foreground, size: 28),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('chat_camera_flip'),
          top: 8,
          right: 8,
          child: _cameras.length > 1 && !_recordingGate.isRecording
              ? Semantics(
                  identifier: 'chat_camera_flip',
                  button: true,
                  enabled: _canSwitchCamera,
                  label: l10n.switchCamera,
                  child: IconButton(
                    onPressed: _canSwitchCamera ? _switchCamera : null,
                    icon: Icon(
                      Icons.flip_camera_ios,
                      color: _canSwitchCamera
                          ? foreground
                          : foreground.withValues(alpha: 0.4),
                      size: 28,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Positioned(
          key: const ValueKey('chat_camera_recording_pill'),
          top: 16,
          left: 0,
          right: 0,
          child: _recordingGate.isRecording
              ? Center(
                  child: Semantics(
                    identifier: 'chat_camera_recording_pill',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _recordingColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fiber_manual_record,
                            color: foreground,
                            size: 12,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatElapsed(_recordingElapsed),
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Positioned(
          key: const ValueKey('chat_camera_controls'),
          bottom: 32,
          left: 0,
          right: 0,
          child: Semantics(
            identifier: 'chat_camera_controls',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_interruptionNotice != null && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      identifier: 'chat_camera_interruption_notice',
                      child: Container(
                        key: const ValueKey('chat_camera_interruption_notice'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.cameraCaptureOverlayColor ??
                              DefaultPalette.cameraCaptureOverlay,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _interruptionNotice!,
                          textAlign: TextAlign.center,
                          style: _hintStyle(emphasis: true),
                        ),
                      ),
                    ),
                  ),
                if (_error == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _recordingGate.isRecording
                          ? l10n.cameraRecordingHint
                          : l10n.cameraTapForPhoto,
                      style: _hintStyle(),
                    ),
                  ),
                _buildCaptureButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _hintStyle({bool emphasis = false}) {
    final base =
        widget.theme.cameraCaptureHintStyle ??
        TextStyle(color: _foreground.withValues(alpha: 0.7), fontSize: 13);
    return emphasis ? base.copyWith(color: _foreground) : base;
  }

  Widget _buildPreview() {
    if (_initializing) {
      return Center(child: CircularProgressIndicator(color: _foreground));
    }
    if (_error != null) {
      return Center(
        key: const ValueKey('chat_camera_error'),
        child: Semantics(
          identifier: 'chat_camera_error',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _foreground, fontSize: 16),
                ),
                if (_showSettingsCta) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      identifier: 'chat_camera_open_settings',
                      child: FilledButton(
                        key: const ValueKey('chat_camera_open_settings'),
                        onPressed: openAppSettings,
                        child: Text(_l10n.openSettings),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // Pinch lives on its own detector wrapping only the live preview — a
    // sibling of the shutter's detector inside the Stack, never an ancestor
    // of it, so the two never compete in the same gesture arena.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1 / controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  /// Applies the pinch one call at a time, and only records the zoom the lens
  /// actually took: committing it up front left `_currentZoom` — and with it
  /// the next pinch's `_baseZoom` — describing a zoom the lens had refused,
  /// and concurrent updates could resolve out of order.
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null) return;
    if (_maxZoom <= _minZoom) return;
    final zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (zoom == _currentZoom) return;
    _requestedZoom = zoom;
    if (_applyingZoom) return;
    _applyingZoom = true;
    try {
      while (_requestedZoom != null) {
        final next = _requestedZoom!;
        _requestedZoom = null;
        final controller = _controller;
        if (controller == null) return;
        try {
          await controller.setZoomLevel(next);
          if (!identical(controller, _controller)) return;
          _currentZoom = next;
        } on Object catch (error, stack) {
          // Some lenses reject an in-range zoom value; the preview must not
          // die for a gesture that only adjusts framing.
          uiDebugLog(
            'CameraCapturePage',
            'setZoomLevel($next) failed: $error\n$stack',
          );
        }
      }
    } finally {
      _applyingZoom = false;
    }
  }

  Widget _buildCaptureButton() {
    final controller = _controller;
    final ready =
        controller != null &&
        controller.value.isInitialized &&
        !_initializing &&
        !_binding &&
        !_recordingGate.isStopping;
    final isRecording = _recordingGate.isRecording;

    return CameraCaptureButton(
      key: const ValueKey('chat_camera_shutter'),
      ready: ready,
      isRecording: isRecording,
      theme: widget.theme,
      // While recording, tapping the shutter finishes and sends the clip —
      // it is no longer a dead tap.
      onTap: ready ? (isRecording ? _stopRecording : _takePicture) : null,
      onRecordStart: ready ? _startRecording : null,
      onRecordStop: ready ? _stopRecording : null,
      onRecordCancel: ready ? _cancelHold : null,
    );
  }
}

/// The shutter of [CameraCapturePage]: tap to shoot, hold to record.
///
/// Exported on its own so a host can drop it into a custom capture screen
/// and keep the SDK's accessibility wiring and hold-to-record semantics.
class CameraCaptureButton extends StatelessWidget {
  const CameraCaptureButton({
    required this.ready,
    required this.isRecording,
    super.key,
    this.theme = ChatTheme.defaults,
    this.onTap,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
  });

  final bool ready;
  final bool isRecording;
  final ChatTheme theme;
  final VoidCallback? onTap;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;

  /// Fired when the press is cancelled instead of released — a permission
  /// dialog stealing the touch, mostly. `onRecordStop` never fires for those.
  final VoidCallback? onRecordCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final foreground =
        theme.cameraCaptureForegroundColor ??
        DefaultPalette.cameraCaptureForeground;
    final size =
        theme.cameraCaptureShutterSize ?? RoomDefaults.cameraShutterSize;
    final color = isRecording
        ? (theme.cameraCaptureRecordingColor ??
              DefaultPalette.cameraCaptureRecording)
        : foreground;

    return Semantics(
      identifier: 'chat_camera_shutter',
      button: true,
      label: isRecording ? l10n.cameraRecordingHint : l10n.cameraTapForPhoto,
      // The actions have to live on this node: `ExcludeSemantics` below keeps
      // the `GestureDetector` from announcing itself twice, but it also drops
      // its actions, leaving the shutter inert for screen readers.
      onTap: onTap,
      onLongPress: onRecordStart,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: onRecordStart == null
              ? null
              : (_) => onRecordStart!(),
          onLongPressEnd: onRecordStop == null ? null : (_) => onRecordStop!(),
          onLongPressCancel: onRecordCancel,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: foreground, width: 4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              // Always a circle — only the fill colour reports the state, so
              // the shutter never morphs mid-gesture.
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
