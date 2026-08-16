import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../_internal/ui_debug_log.dart';
import '../models/camera_capture_result.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';

/// Playable preview of a clip that has just been recorded and is waiting to
/// be sent — the video half of [CameraCaptureReview].
///
/// Tap anywhere on the frame to start playback and tap again to pause; a
/// clip that ran to the end restarts from the first frame. There is no
/// scrubber on purpose: this is a "is this the take I want?" screen, not a
/// player, and every extra control competes with the two decisions the step
/// exists for (send or shoot again).
///
/// Backed by `video_player`. A clip the platform decoder cannot open still
/// renders — as a static placeholder — because the user must remain able to
/// send or discard a capture whose preview failed. Hosts that would rather
/// not ship `video_player` at all replace this widget wholesale through
/// `CameraCapturePage(videoPreviewBuilder: …)`.
class CameraVideoPreview extends StatefulWidget {
  const CameraVideoPreview({
    required this.file,
    super.key,
    this.theme = ChatTheme.defaults,
  });

  /// The clip on disk, exactly as the camera plugin wrote it.
  final XFile file;

  final ChatTheme theme;

  @override
  State<CameraVideoPreview> createState() => _CameraVideoPreviewState();
}

class _CameraVideoPreviewState extends State<CameraVideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  /// Names the open attempt the widget is currently waiting on.
  ///
  /// `VideoPlayerController.initialize()` is a real platform round-trip, and
  /// [didUpdateWidget] can hand over a third take while the second one is
  /// still opening. Without a token every attempt that resolves would claim
  /// [_controller], and the ones it overwrote would stay alive for the rest
  /// of the process — a native decoder session per superseded take, holding
  /// its file open, ticking into a listener nobody reads. Same generation
  /// idiom `CameraRecordingGate` uses for the start/stop race.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(CameraVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path == widget.file.path) return;
    // A second take handed to the same widget. Without this the screen keeps
    // playing the clip that was thrown away.
    _retire();
    _failed = false;
    unawaited(_open());
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  /// Ends the current attempt: drops the live controller if there is one and
  /// bumps the generation so an open still in flight releases its own
  /// controller instead of mounting it.
  void _retire() {
    _generation++;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onPlayerTick);
    unawaited(_release(controller));
  }

  /// Releases the player without letting a failing teardown escape: the
  /// native session is routinely gone already once the capture screen is
  /// leaving, and there is nothing left to salvage either way.
  Future<void> _release(VideoPlayerController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } on Object catch (error) {
      uiDebugLog('CameraVideoPreview', 'dispose failed: $error');
    }
  }

  Future<void> _open() async {
    final generation = _generation;
    final controller = VideoPlayerController.file(File(widget.file.path));
    try {
      await controller.initialize();
    } on Object catch (error, stack) {
      // Not just `Exception`: a missing platform implementation raises a
      // `MissingPluginException`, and a decoder that rejects the container
      // signs off with a `PlatformException`. Neither may take the review
      // step down — the capture is still perfectly sendable.
      uiDebugLog('CameraVideoPreview', 'initialize failed: $error\n$stack');
      unawaited(_release(controller));
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
      return;
    }
    if (!mounted || generation != _generation) {
      // Superseded (or torn down) while the platform was opening the file:
      // this controller is nobody's, so it goes back where it came from.
      unawaited(_release(controller));
      return;
    }
    controller.addListener(_onPlayerTick);
    setState(() => _controller = controller);
  }

  void _onPlayerTick() {
    if (!mounted) return;
    // The play / pause overlay is the only thing reading the player, and it
    // only cares about the flag — position updates land on the same frame
    // budget as everything else on this screen.
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
        return;
      }
      // A clip left sitting on its last frame has nothing to resume into:
      // `play()` alone would report "playing" and never advance.
      if (controller.value.isCompleted) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    } on Object catch (error, stack) {
      uiDebugLog(
        'CameraVideoPreview',
        'playback toggle failed: $error\n$stack',
      );
    }
  }

  Color get _foreground =>
      widget.theme.cameraCaptureForegroundColor ??
      DefaultPalette.cameraCaptureForeground;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10nOf(context);
    final foreground = _foreground;
    if (_failed) {
      return Center(
        child: Icon(
          Icons.videocam_off,
          size: 64,
          color: foreground.withValues(alpha: 0.6),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: foreground));
    }
    final isPlaying = controller.value.isPlaying;
    return Semantics(
      identifier: 'chat_camera_review_play',
      button: true,
      label: isPlaying ? l10n.pausePreview : l10n.playPreview,
      onTap: _togglePlayback,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('chat_camera_review_play'),
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayback,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              if (!isPlaying)
                Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 72,
                    color: foreground.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
