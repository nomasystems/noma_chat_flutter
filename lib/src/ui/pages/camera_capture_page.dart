import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/chat_ui_localizations.dart';
import '../models/camera_capture_result.dart';
import '../room_defaults.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../utils/platform_support.dart';
import 'camera_recording_gate.dart';

/// Full-screen in-app camera: tap the shutter for a still, hold it to
/// record a clip. Pops with a [CameraCaptureResult], or `null` when the
/// user backs out.
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
  const CameraCapturePage({super.key, this.theme = ChatTheme.defaults});

  final ChatTheme theme;

  /// Pushes the capture screen and returns what the user shot, or `null`
  /// on cancellation (and on platforms without an in-app camera).
  static Future<CameraCaptureResult?> show({
    required BuildContext context,
    ChatTheme theme = ChatTheme.defaults,
    bool fullscreenDialog = true,
  }) {
    if (!PlatformSupport.supportsInAppCameraCapture) {
      return Future<CameraCaptureResult?>.value();
    }
    return Navigator.of(context).push<CameraCaptureResult>(
      MaterialPageRoute<CameraCaptureResult>(
        fullscreenDialog: fullscreenDialog,
        builder: (_) => CameraCapturePage(theme: theme),
      ),
    );
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
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
  // Kept apart from [_error]: rebinding the preview clears the error, and the
  // user still has to learn that the clip they were recording is gone.
  String? _interruptionNotice;

  ChatUiLocalizations get _l10n => widget.theme.l10nOf(context);

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
    _controller?.dispose();
    super.dispose();
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
    final cameraStatus = await Permission.camera.request();
    // Read-only: a still photo does not need audio, so the microphone prompt
    // is deferred to the first hold-to-record gesture.
    _microphoneGranted = await Permission.microphone.isGranted;
    await _applyCameraPermissionStatus(cameraStatus);
  }

  Future<void> _recheckCameraPermission() async {
    await _applyCameraPermissionStatus(await Permission.camera.status);
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

  Future<void> _bindCameraAfterPermissions() async {
    if (!_cameraGranted || _binding) return;
    _binding = true;
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
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _l10n.cameraUnavailable;
      });
    } finally {
      _binding = false;
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
    } on Exception catch (_) {
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
    } on Exception catch (_) {
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
    } on Exception catch (_) {
      // Nothing to salvage: the session is gone either way.
    }
  }

  bool get _canSwitchCamera =>
      _cameras.length > 1 &&
      !_recordingGate.isRecording &&
      !_recordingGate.isStarting &&
      !_binding &&
      !_initializing;

  Future<void> _switchCamera() async {
    if (!_canSwitchCamera) return;
    final previousIndex = _activeCameraIndex;
    final next = (previousIndex + 1) % _cameras.length;
    _binding = true;
    final outgoing = _controller;
    setState(() {
      _controller = null;
      _initializing = true;
      _interruptionNotice = null;
    });
    await _disposeQuietly(outgoing);
    try {
      await _bindCamera(next);
    } on Exception catch (_) {
      await _recoverPreviousCamera(previousIndex);
    } finally {
      _binding = false;
    }
  }

  Future<void> _recoverPreviousCamera(int previousIndex) async {
    final stale = _controller;
    _controller = null;
    await _disposeQuietly(stale);
    if (!mounted) return;
    try {
      await _bindCamera(previousIndex);
    } on Exception catch (_) {
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
      Navigator.of(
        context,
      ).pop(CameraCaptureResult(file: file, isVideo: false));
    } on Exception catch (_) {
      if (!mounted) return;
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
    try {
      await controller.startVideoRecording();
    } on Object catch (_) {
      // Not just `Exception`: a teardown that lands mid-start disposes the
      // controller, and `startVideoRecording` signs off by writing to it,
      // which fails an assertion rather than throwing. Either way there is no
      // recording, and a retired attempt has nobody left to report to.
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
    if (outcome == CameraStartOutcome.stale) return;
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
      _recordingGate.reset();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.microphonePermissionDenied),
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
    if (!_recordingGate.requestStop()) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      if (!mounted) return;
      setState(() => _recordingElapsed = Duration.zero);
      return;
    }
    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recordingElapsed = Duration.zero);
      Navigator.of(context).pop(CameraCaptureResult(file: file, isVideo: true));
    } on Exception catch (_) {
      _recordingGate.reset();
      if (!mounted) return;
      setState(() {
        _recordingElapsed = Duration.zero;
        _error = _l10n.cameraUnavailable;
      });
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
    final l10n = _l10n;
    final foreground = _foreground;
    return Scaffold(
      backgroundColor:
          theme.cameraCaptureBackgroundColor ??
          DefaultPalette.cameraCaptureBackground,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            Positioned(
              top: 8,
              left: 8,
              child: Semantics(
                button: true,
                label: l10n.close,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: foreground, size: 28),
                ),
              ),
            ),
            if (_cameras.length > 1 && !_recordingGate.isRecording)
              Positioned(
                top: 8,
                right: 8,
                child: Semantics(
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
                ),
              ),
            if (_recordingGate.isRecording)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
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
              ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_interruptionNotice != null && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
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
          ],
        ),
      ),
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
                  child: FilledButton(
                    onPressed: openAppSettings,
                    child: Text(_l10n.openSettings),
                  ),
                ),
              ],
            ],
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

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    final controller = _controller;
    if (controller == null) return;
    if (_maxZoom <= _minZoom) return;
    final zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (zoom == _currentZoom) return;
    _currentZoom = zoom;
    try {
      await controller.setZoomLevel(zoom);
    } on Exception catch (_) {
      // Some lenses reject an in-range zoom value; the preview must not die
      // for a gesture that only adjusts framing.
    }
  }

  Widget _buildCaptureButton() {
    final controller = _controller;
    final ready =
        controller != null &&
        controller.value.isInitialized &&
        !_initializing &&
        !_binding;
    final isRecording = _recordingGate.isRecording;

    return CameraCaptureButton(
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
