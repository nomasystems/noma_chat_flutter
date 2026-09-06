part of 'camera_capture_page.dart';

/// What the capture page paints: the live viewfinder and its mirroring,
/// the still or video review that follows a capture, the pinch-to-zoom
/// gesture the viewfinder answers and the shutter button itself.
extension _CameraCaptureView on _CameraCapturePageState {
  /// Rewrites [file] so the still matches the viewfinder it was framed in.
  ///
  /// Front lenses preview mirrored on every platform the SDK builds for
  /// (`camera_avfoundation` mirrors the video connection, `camera_android_
  /// camerax` mirrors the preview widget) while the file the sensor writes
  /// is not, so a selfie comes back reversed against the picture the user
  /// was looking at. Flipping it here — at the source, before the review
  /// step ever reads the path — is what makes the take, the file that gets
  /// sent and the bubble's thumbnail agree.
  ///
  /// Never throws: a capture that cannot be decoded is worth sending as it
  /// came, and this runs inside the shutter's own error handling.
  Future<void> _matchViewfinderMirror(XFile file) async {
    try {
      final source = File(file.path);
      final bytes = await source.readAsBytes();
      final flipped = PlatformSupport.supportsBackgroundIsolates
          ? await compute(
              _flipStillHorizontally,
              bytes,
              debugLabel: 'noma_chat capture mirror',
            )
          : _flipStillHorizontally(bytes);
      if (flipped == null) return;
      await source.writeAsBytes(flipped, flush: true);
    } on Object catch (error, stack) {
      uiDebugLog(
        'CameraCapturePage',
        'could not match the viewfinder mirror: $error\n$stack',
      );
    }
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
        allowCaption: widget.allowCaption,
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

  /// Turns the gesture over the preview into a zoom.
  ///
  /// Two fingers pinch, in every mode. One finger zooms only while a clip is
  /// recording, and by how far it slides rather than by a scale factor it
  /// cannot carry: hold-to-record pins a finger to the shutter, so a pinch on
  /// the preview is a gesture the user has no hand left to make.
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (details.pointerCount != _zoomPointers) {
      _anchorZoomGesture(details.pointerCount, details.localFocalPoint.dy);
      return;
    }
    if (details.pointerCount > 1) {
      await _applyZoom(_baseZoom * details.scale);
      return;
    }
    if (!_recordingGate.isRecording) return;
    await _applyZoom(
      _zoomForTravel(_baseZoom, _dragZoomOrigin - details.localFocalPoint.dy),
    );
  }

  /// The lens factor [travel] logical pixels of slide are worth, starting
  /// from [base]. Geometric rather than linear: a lens that reports a maximum
  /// of a hundred and something — most back cameras do — would otherwise put
  /// its whole range inside the first twitch of the finger.
  double _zoomForTravel(double base, double travel) {
    final floor = _minZoom > 0 ? _minZoom : 1.0;
    return math.max(base, floor) *
        math.pow(_maxZoom / floor, travel / _dragZoomTravel);
  }

  /// Applies a zoom one call at a time, and only records the zoom the lens
  /// actually took: committing it up front left `_currentZoom` — and with it
  /// the next gesture's base — describing a zoom the lens had refused, and
  /// concurrent updates could resolve out of order.
  Future<void> _applyZoom(double target) async {
    if (_controller == null) return;
    if (_maxZoom <= _minZoom) return;
    final zoom = target.clamp(_minZoom, _maxZoom);
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
      onRecordZoom: ready ? _handleShutterZoom : null,
    );
  }
}
