import 'dart:async';

/// Owns the per-room throttle window + auto-stop timer for typing
/// indicators. The pattern (Slack/Telegram-style):
///
/// - When the user is typing, send `startsTyping` at most every
///   [throttle] (default 3s) to avoid flooding the backend.
/// - When the user stops typing for [stopDelay] (default 1s), send a
///   `stopsTyping` automatically — even if the caller doesn't.
///
/// The registry holds two pieces of state per room: the last
/// `startsTyping` send timestamp (for throttling) and the active
/// stop-delay timer. The adapter (or its event router) consumes the
/// registry via [recordStartTyping] / [recordStopTyping] and wires
/// [onAutoStopTriggered] to fire the actual network call.
///
/// Tests use `FakeAsync` to drive the timer deterministically.
class TypingTimerRegistry {
  TypingTimerRegistry({
    required void Function(String roomId) onAutoStopTriggered,
    this.throttle = const Duration(seconds: 3),
    this.stopDelay = const Duration(seconds: 1),
  }) : _onAutoStopTriggered = onAutoStopTriggered;

  final Duration throttle;
  final Duration stopDelay;
  final void Function(String roomId) _onAutoStopTriggered;

  final Map<String, DateTime> _lastStartSent = {};
  final Map<String, Timer> _stopTimers = {};
  DateTime Function() _now = DateTime.now;

  /// Test seam — override to inject a deterministic clock. The default
  /// is `DateTime.now` which is what production wants.
  set clockOverride(DateTime Function() clock) => _now = clock;

  /// Records intent to send `startsTyping` to [roomId]. Returns `true`
  /// when the caller should actually fire the network request, `false`
  /// when the call is throttled (last `startsTyping` for this room was
  /// less than [throttle] ago).
  ///
  /// Always schedules / replaces the auto-stop timer for [roomId] so
  /// that — if the caller goes silent for [stopDelay] — the registry
  /// fires [onAutoStopTriggered] on its own.
  bool recordStartTyping(String roomId) {
    _stopTimers[roomId]?.cancel();
    _stopTimers[roomId] = Timer(stopDelay, () {
      _stopTimers.remove(roomId);
      _lastStartSent.remove(roomId);
      _onAutoStopTriggered(roomId);
    });
    final last = _lastStartSent[roomId];
    if (last != null && _now().difference(last) < throttle) {
      return false;
    }
    _lastStartSent[roomId] = _now();
    return true;
  }

  /// Records intent to send `stopsTyping` to [roomId] (user explicitly
  /// cleared the composer / pressed send). Cancels the pending
  /// auto-stop timer and clears the throttle window so the next
  /// `startsTyping` won't be throttled.
  void recordStopTyping(String roomId) {
    _stopTimers[roomId]?.cancel();
    _stopTimers.remove(roomId);
    _lastStartSent.remove(roomId);
  }

  /// Cancels every active timer and clears throttle state. Does NOT
  /// fire [onAutoStopTriggered]. Called from `logout()` / `dispose()`.
  void clearAll() {
    for (final timer in _stopTimers.values) {
      timer.cancel();
    }
    _stopTimers.clear();
    _lastStartSent.clear();
  }

  /// Diagnostics: number of rooms with an active stop timer.
  int get activeTimerCount => _stopTimers.length;
}
