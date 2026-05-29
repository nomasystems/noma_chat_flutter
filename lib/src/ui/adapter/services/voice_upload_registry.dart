import 'package:flutter/foundation.dart';

/// Tracks per-message upload progress notifiers (0..1) for voice
/// messages currently uploading.
///
/// Lifecycle is split into three states so the audio bubble's
/// progress indicator behaves correctly across the optimistic send →
/// upload → confirm path:
///
/// 1. **Active**: the notifier is in [_active], the bubble subscribes
///    to it, upload progress drives `notifier.value`.
/// 2. **Completed**: upload succeeded; the notifier moves to [_detached]
///    so the bubble can still listen (and observe the final `1.0`)
///    until its next rebuild swaps the temp id for the server id.
///    Dropping outright would throw on the next bubble read.
/// 3. **Failed**: upload failed; the notifier is dropped from active
///    without retention. The failed-bubble UI doesn't need it
///    anymore — failure is signalled via the message's `isFailed`
///    flag, not via the progress notifier.
///
/// `disposeAll()` is the catch-all teardown — called from
/// `ChatUiAdapter.dispose()`.
class VoiceUploadRegistry {
  final Map<String, ValueNotifier<double>> _active = {};
  final List<ValueNotifier<double>> _detached = [];

  /// Registers a fresh notifier for [tempId] and returns it. The
  /// notifier starts at `0.0`. Caller drives `notifier.value` during
  /// upload progress and then calls [complete] or [drop].
  ValueNotifier<double> register(String tempId) {
    final notifier = ValueNotifier<double>(0.0);
    _active[tempId] = notifier;
    return notifier;
  }

  /// Read-only listenable for [tempId], or `null` when no upload is
  /// active for that id. Used by `ChatUiAdapter.voiceUploadProgressFor`
  /// (the public API consumed by `AudioBubble`).
  ValueListenable<double>? listenableFor(String tempId) => _active[tempId];

  /// `true` while [tempId] has an active upload notifier. Used by the
  /// progress callback to guard against late `onProgress` ticks
  /// arriving after the upload has been dropped (e.g. adapter
  /// disposed mid-upload).
  bool isActive(String tempId) => _active.containsKey(tempId);

  /// Returns the active notifier for [tempId] — exposed because the
  /// adapter occasionally needs identity comparison (`map[id] ==
  /// localProgress`) to detect that another path has already replaced
  /// the notifier. Most callers should prefer [listenableFor].
  ValueNotifier<double>? rawNotifier(String tempId) => _active[tempId];

  /// Moves the notifier for [tempId] from active to detached. Used on
  /// upload success: the bubble can still observe `1.0` until its
  /// next rebuild swaps the temp id for the server id. Also flips the
  /// value to `1.0` defensively so any late subscriber sees the
  /// completed state.
  ///
  /// No-op when [tempId] isn't active (e.g. duplicate complete call).
  void complete(String tempId) {
    final notifier = _active.remove(tempId);
    if (notifier == null) return;
    notifier.value = 1.0;
    _detached.add(notifier);
  }

  /// Drops the active entry for [tempId] without retaining. Used on
  /// upload failure: the failed-bubble UI signals failure via
  /// `message.isFailed`, not the progress notifier. The dropped
  /// notifier becomes GC-able once the bubble rebuilds.
  ///
  /// No-op when [tempId] isn't active.
  void drop(String tempId) {
    _active.remove(tempId);
  }

  /// Releases every notifier — active AND detached. Called from
  /// `ChatUiAdapter.dispose()` and `ChatUiAdapter.logout()`.
  void disposeAll() {
    for (final n in _active.values) {
      n.dispose();
    }
    _active.clear();
    for (final n in _detached) {
      n.dispose();
    }
    _detached.clear();
  }

  /// Diagnostics — count of active uploads.
  int get activeCount => _active.length;

  /// Diagnostics — count of detached (completed-but-retained) notifiers.
  int get detachedCount => _detached.length;
}
