import 'package:flutter/foundation.dart';

import '../../../models/attachment.dart';

/// Tracks per-message [UploadCancelToken]s for photo/video/file attachments
/// currently uploading via `ChatMessagesController.sendAttachment`, plus the
/// listenable that tells the bubble whether cancelling is still possible.
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
  /// [cancelAll]. A mark nobody asks about is released by [retire], so the
  /// set cannot outlive the send that produced it.
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
  void retire(String tempId) {
    drop(tempId);
    _cancellable.remove(tempId);
    _userCancelled.remove(tempId);
  }

  /// Cancels and releases every outstanding token. Called from
  /// `ChatUiAdapter`'s session teardown, mirroring
  /// `VoiceUploadRegistry.disposeAll`. Never marks an id as user-cancelled
  /// — see [consumeUserCancelled].
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
