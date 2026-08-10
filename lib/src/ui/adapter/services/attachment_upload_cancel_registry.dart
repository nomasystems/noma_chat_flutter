import '../../../models/attachment.dart';

/// Tracks per-message [UploadCancelToken]s for photo/video/file attachments
/// currently uploading via `ChatMessagesController.sendAttachment`.
///
/// Sibling to [VoiceUploadRegistry] rather than a merged concern: a
/// progress notifier and a cancel token have unrelated lifecycles. A
/// notifier survives briefly past completion so the bubble can observe the
/// final `1.0` (`VoiceUploadRegistry.complete`'s "detached" state); a
/// cancel token is meaningless the instant the upload settles — success,
/// failure, or cancellation all just [drop] it, no equivalent detached
/// state needed.
class AttachmentUploadCancelRegistry {
  final Map<String, UploadCancelToken> _tokens = {};
  final Set<String> _userCancelled = {};

  /// Creates a fresh token for [tempId], stores it, and returns it. The
  /// caller hands the same instance to `ChatAttachmentsApi.upload(cancelToken:
  /// …)` and calls [drop] once the upload settles on its own.
  UploadCancelToken register(String tempId) {
    final token = UploadCancelToken();
    _tokens[tempId] = token;
    _userCancelled.remove(tempId);
    return token;
  }

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
    _userCancelled.add(tempId);
    token.cancel();
    return true;
  }

  /// Whether [tempId]'s upload was aborted through [cancel] — the bubble's
  /// X — rather than through the bulk [cancelAll] teardown, forgetting the
  /// record in the process (so the set cannot grow across a session).
  ///
  /// Both routes surface the same `CancelledFailure` at the upload's call
  /// site, but they mean opposite things: the user abandoning a message
  /// deletes its provisional bubble, a session going away must leave it
  /// alone. Asking here keeps that distinction independent of the order in
  /// which a teardown happens to call `cancelPendingRequests` and
  /// `cancelAll`.
  bool consumeUserCancelled(String tempId) => _userCancelled.remove(tempId);

  /// Drops the entry for [tempId] without cancelling — the upload settled
  /// on its own (success or a genuine failure) and the token is no longer
  /// needed.
  ///
  /// No-op when [tempId] isn't registered.
  void drop(String tempId) {
    _tokens.remove(tempId);
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
    _userCancelled.clear();
  }

  /// Diagnostics — count of tokens currently tracked.
  int get activeCount => _tokens.length;
}
