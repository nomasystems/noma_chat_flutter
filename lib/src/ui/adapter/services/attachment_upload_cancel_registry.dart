import 'package:flutter/foundation.dart';

import '../../../models/attachment.dart';

/// Tracks per-message [UploadCancelToken]s for every blob on the wire —
/// photo, video, file (`ChatMessagesController.sendAttachment`), the poster
/// frame of a video, and recorded voice clips (`sendVoice`) — plus the
/// listenable that tells the bubble whether cancelling is still possible.
///
/// Every upload the adapter *itself* drives registers here, because this is
/// what the session teardown walks: `ChatUiAdapter` calls [cancelAll] the
/// moment a session ends, and an upload absent from this map is one nothing
/// can stop. It then lands for a session that is gone, referenced by no
/// message, billed to the user with no API to reclaim it. Three upload
/// paths are deliberately outside that set, and none of them can produce
/// that orphan:
///
/// * `ChatMessagesController.uploadAttachment` — the host asked for the
///   blob without a message, so the adapter has no temp id to file it
///   under and no bubble to take down. The signature accepts the host's own
///   [UploadCancelToken] instead: whoever owns the send owns the abort.
/// * `NomaChatClient`'s offline-queue replay — it runs *because* a session
///   came back, not inside one, and re-drives the whole upload + send under
///   the queue's own retry.
/// * `DefaultAvatarStorage` — a profile picture, not a message; nothing
///   references it by temp id and it is not lost by a logout.
///
/// A cancellability signal is registered for voice clips like any other
/// blob, but no bubble reads it: `AudioBubble` paints no progress ring, so
/// there is no X to put on it. A clip is aborted by the teardown, or by a
/// host calling `ChatUiAdapter.cancelAttachmentUpload` itself.
///
/// Sibling to [VoiceUploadRegistry] rather than a merged concern: progress
/// and cancellability are two signals with different lifetimes. The ring
/// runs until the row reaches a real final state — bytes up, poster frame
/// up, send acknowledged — because retiring it earlier would leave the
/// bubble resolving an attachment URL that does not exist yet. Cancelling
/// stops being possible the instant the bytes land, long before that. One
/// notifier cannot mean both, so the cancel side lives here.
class AttachmentUploadCancelRegistry {
  final Map<String, UploadCancelToken> _tokens = {};
  final Map<String, ValueNotifier<bool>> _cancellable = {};
  final Set<String> _userCancelled = {};

  /// Creates a fresh token for [tempId], stores it, and returns it. The
  /// caller hands the same instance to `ChatAttachmentsApi.upload(cancelToken:
  /// …)` and calls [drop] once the upload settles on its own, then [retire]
  /// once the whole send is over.
  UploadCancelToken register(String tempId) {
    final token = UploadCancelToken();
    _tokens[tempId] = token;
    _cancellable[tempId] = ValueNotifier<bool>(true);
    _userCancelled.remove(tempId);
    return token;
  }

  /// Whether [tempId]'s upload can still be aborted, as a listenable so a
  /// ring already built keeps no stale X: [drop]/[cancel]/[cancelAll] flip
  /// the value in place and the bubble rebuilds without the button.
  ///
  /// `null` once [retire] has run (or for an id that never uploaded) — by
  /// then the progress notifier is gone too, so there is no ring to put an
  /// X on.
  ///
  /// The instance handed out here is never disposed by this registry — see
  /// [retire] — so a host that resolves the signal once and keeps it can go
  /// on adding and removing listeners after the send is over. It simply
  /// stays `false` forever.
  ValueListenable<bool>? cancellableFor(String tempId) => _cancellable[tempId];

  /// Cancels and removes the token for [tempId]. Returns `true` when an
  /// upload was actually in flight for that id, `false` if it already
  /// settled (or never existed) — the caller uses this to decide whether
  /// there is anything left to clean up.
  ///
  /// Records the id as user-initiated so [consumeUserCancelled] can tell
  /// this apart from [cancelAll].
  bool cancel(String tempId) {
    final token = _tokens.remove(tempId);
    if (token == null) return false;
    _cancellable[tempId]?.value = false;
    _userCancelled.add(tempId);
    token.cancel();
    return true;
  }

  /// Whether [tempId]'s upload was aborted through [cancel] — the bubble's
  /// X — rather than through the bulk [cancelAll] teardown, forgetting the
  /// record in the process.
  ///
  /// Both routes surface the same `CancelledFailure` at the upload's call
  /// site, but they mean opposite things: the user abandoning a message
  /// deletes its provisional bubble, a session going away must leave it
  /// alone. Asking here keeps that distinction independent of the order in
  /// which a teardown happens to call `cancelPendingRequests` and
  /// [cancelAll]. A mark nobody asks about is released by [retire] (and by
  /// [cancelAll]), so the set cannot outlive the send that produced it.
  bool consumeUserCancelled(String tempId) => _userCancelled.remove(tempId);

  /// Drops the token for [tempId] without cancelling — the upload settled
  /// on its own (success or a genuine failure) — and marks the id
  /// un-cancellable. The send that follows (poster frame, then the message)
  /// carries on with the ring up and the X gone.
  ///
  /// No-op when [tempId] isn't registered.
  void drop(String tempId) {
    _tokens.remove(tempId);
    _cancellable[tempId]?.value = false;
  }

  /// Releases everything held for [tempId] — token, cancellability signal
  /// and any user-cancelled mark. Called from the `finally` that closes a
  /// send, so no exit path can leave an entry behind.
  ///
  /// The signal is flipped to `false` (by [drop]) and then let go of, never
  /// disposed. [cancellableFor] publishes that very instance through the
  /// public `ChatUiAdapter.attachmentUploadCancellableFor`, and a host is
  /// entitled to hold on to what a public getter returned: disposing it
  /// here would turn its next `addListener` — a `didUpdateWidget`, a
  /// re-inserted element, a `ValueListenableBuilder` rebuilt over the
  /// cached instance — into a `FlutterError` on the UI thread. Letting go
  /// leaves nothing behind either way, because the notifier owns no
  /// resource beyond its own listener list, and that list is a field of the
  /// notifier: it is collected with it once this map and the host have both
  /// dropped the reference. Retention runs notifier → listener, so an
  /// undisposed notifier cannot pin a widget alive either.
  void retire(String tempId) {
    drop(tempId);
    _cancellable.remove(tempId);
    _userCancelled.remove(tempId);
  }

  /// Cancels and releases every outstanding token. Called from
  /// `ChatUiAdapter`'s session teardown. Never marks an id as
  /// user-cancelled — see [consumeUserCancelled].
  ///
  /// Signals are flipped to `false` first, so a ring already on screen
  /// loses its X, and then released on [retire]'s terms: dropped, never
  /// disposed, because the same instances were published through a public
  /// getter and a host may still be listening to them.
  ///
  /// User-cancelled marks go with them. Preserving a mark across a teardown
  /// would buy nothing: this method only ever runs from
  /// `ChatUiAdapter._resetConnectionState`, on the same line of execution
  /// as the session-epoch bump, and both call sites that ask
  /// [consumeUserCancelled] — `ChatMessagesController.sendAttachment` and
  /// `sendVoice` — test that epoch and return the "session ended" failure
  /// before their user-cancelled branch can read the answer. So the mark is
  /// unreachable after a teardown, and keeping it is state surviving an
  /// operation whose job is to wipe state.
  void cancelAll() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    for (final signal in _cancellable.values) {
      signal.value = false;
    }
    _cancellable.clear();
    _userCancelled.clear();
  }

  /// Diagnostics — count of tokens currently tracked.
  int get activeCount => _tokens.length;
}
