/// What [CameraRecordingGate.completeStart] resolved the start attempt to.
enum CameraStartOutcome {
  /// The gate is armed: show the recording UI.
  recording,

  /// The finger lifted while the start was still in flight — stop right
  /// away instead of showing the recording UI.
  stopImmediately,

  /// The attempt belongs to a camera session that was retired while the
  /// start was in flight (a lifecycle teardown, a lens switch). The gate
  /// stays clear and there is nothing left to stop.
  stale,
}

/// Gesture-state machine backing [CameraCapturePage]'s hold-to-record
/// button. Isolated from `CameraController` so the start/stop race can be
/// unit-tested without a real camera.
///
/// `startVideoRecording()` is async; a release before it resolves must not
/// be lost (it used to leave the recording running with no way to stop it).
/// [requestStop] absorbs that early release and [completeStart] replays it
/// the moment the start call resolves.
///
/// Every attempt carries the generation token [beginStart] hands out, so a
/// start that resolves *after* the gate was cleared is recognised as
/// [CameraStartOutcome.stale] instead of re-arming a gate whose controller
/// no longer exists.
class CameraRecordingGate {
  int _generation = 0;
  bool _starting = false;
  bool _recording = false;
  bool _stopping = false;
  bool _stopRequestedDuringStart = false;

  bool get isRecording => _recording;
  bool get isStarting => _starting;

  /// `true` between [requestStop] and [completeStop] — the platform is still
  /// finalising the clip. Its own state because the gate is no longer
  /// recording yet the camera is not free either: without it a teardown
  /// landing inside that round-trip reads as "nothing was active" and the
  /// clip disappears with no notice.
  bool get isStopping => _stopping;

  /// The session the gate is tracking right now. Capture it before an await
  /// and hand it to [isStale] afterwards to tell whether the session the call
  /// belonged to outlived it.
  int get currentSession => _generation;

  /// Call before issuing `startVideoRecording()`. Returns the token that
  /// identifies this attempt — hand it back to [completeStart] — or `null`
  /// when a start, a recording or a stop is already in progress.
  int? beginStart() {
    if (_starting || _recording || _stopping) return null;
    _starting = true;
    _stopRequestedDuringStart = false;
    return _generation;
  }

  /// Call after `startVideoRecording()` fails, before it ever resolved.
  void reset() {
    // Clearing the gate ends the attempt the outstanding token names: bumping
    // the generation is what stops a start still in flight from claiming it.
    _generation++;
    _starting = false;
    _recording = false;
    _stopping = false;
    _stopRequestedDuringStart = false;
  }

  /// `true` when [token] no longer names the attempt the gate is tracking —
  /// something cleared or replaced it while the start was in flight, so its
  /// outcome (success or failure) is about a session nobody is waiting on.
  bool isStale(int? token) => token == null || token != _generation;

  /// Call once `startVideoRecording()` resolves successfully, with the token
  /// [beginStart] returned for that same attempt.
  CameraStartOutcome completeStart(int? token) {
    if (isStale(token) || !_starting) return CameraStartOutcome.stale;
    _starting = false;
    _recording = true;
    if (_stopRequestedDuringStart) {
      _stopRequestedDuringStart = false;
      return CameraStartOutcome.stopImmediately;
    }
    return CameraStartOutcome.recording;
  }

  /// Call before issuing `stopVideoRecording()`. Returns `false` when there
  /// is nothing to stop yet (a start is still in flight — the request is
  /// remembered and replayed by [completeStart] — or nothing was started).
  /// A `true` leaves the gate [isStopping] until [completeStop].
  bool requestStop() {
    if (_starting) {
      _stopRequestedDuringStart = true;
      return false;
    }
    if (!_recording) return false;
    _recording = false;
    _stopping = true;
    return true;
  }

  /// Call once `stopVideoRecording()` resolves, whichever way it went: the
  /// platform is done with the clip and the camera is free again.
  void completeStop() {
    _stopping = false;
  }

  /// Call when the underlying `CameraController` is torn down out from under
  /// the gesture (e.g. an incoming call sends the app to
  /// `AppLifecycleState.inactive` mid-recording). Clears all state so the
  /// gate no longer believes a start or a recording is in progress. Returns
  /// `true` when a start, a recording or a stop still being finalised was
  /// actually interrupted, so the caller knows to tell the user the clip was
  /// lost instead of silently discarding it.
  bool interruptIfActive() {
    final wasActive = _starting || _recording || _stopping;
    reset();
    return wasActive;
  }
}
