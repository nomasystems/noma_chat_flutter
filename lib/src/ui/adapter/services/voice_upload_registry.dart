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
/// 2. **Completed**: upload succeeded; the notifier moves to [_detached],
///    which keeps it reachable from the registry while the bubble finishes
///    observing the final `1.0` — until its next rebuild swaps the temp id
///    for the server id.
/// 3. **Failed**: upload failed; the notifier is dropped from active
///    without retention. The failed-bubble UI doesn't need it
///    anymore — failure is signalled via the message's `isFailed`
///    flag, not via the progress notifier.
///
/// [releaseAll] is the catch-all teardown — called from
/// `ChatUiAdapter._resetSessionState`, so from both `signOut()` and
/// `dispose()`. Nothing here ever destroys a notifier: they leave the SDK
/// through public getters, and what has been handed out is not ours to
/// kill. See [releaseAll].
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
  /// active for that id. This is the object the public getters
  /// `ChatUiAdapter.voiceUploadProgressFor` (consumed by `AudioBubble`) and
  /// `ChatUiAdapter.attachmentUploadProgressFor` (the upload ring on every
  /// other kind of blob) return, so it outlives this registry whenever a
  /// host keeps it — which is why [releaseAll] never destroys one.
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

  /// Lets go of every notifier — active AND detached — without destroying
  /// any of them. Runs from `ChatUiAdapter._resetSessionState`, which means
  /// on every `signOut()`, not only on `dispose()`.
  ///
  /// Deliberately disposes nothing — the same decision
  /// `AttachmentUploadCancelRegistry` took for its cancel signals, and for
  /// the same reason. These notifiers are published by
  /// `ChatUiAdapter.voiceUploadProgressFor` and
  /// `ChatUiAdapter.attachmentUploadProgressFor`, and a host is entitled to
  /// resolve one once and subscribe to it itself instead of re-reading the
  /// getter on every build. Disposing here turns that host's next
  /// `addListener` — a `didUpdateWidget`, a re-inserted element, a
  /// `ValueListenableBuilder` rebuilt over the instance it kept — into
  /// `FlutterError: A ValueNotifier<double> was used after being disposed`,
  /// on the UI thread, in release builds too. Dropping the references
  /// instead costs nothing: a notifier nobody holds is garbage, its listener
  /// list included, and that list can only retain its listeners, never the
  /// other way round.
  ///
  /// No terminal value is published on the way out either, unlike the cancel
  /// registry's `false`. "No upload in flight" is expressed by the getters
  /// answering `null`, not by a number: `1.0` would claim a clip that never
  /// landed and `0.0` an upload back at the start, so the last real progress
  /// is what stays.
  void releaseAll() {
    _active.clear();
    _detached.clear();
  }

  /// Diagnostics — count of active uploads.
  int get activeCount => _active.length;

  /// Diagnostics — count of detached (completed-but-retained) notifiers.
  int get detachedCount => _detached.length;
}
