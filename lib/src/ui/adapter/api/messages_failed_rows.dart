part of '../chat_ui_adapter.dart';

/// What [ChatMessagesController.retrySend] and
/// [ChatMessagesController.discardFailed] do to a failed optimistic row:
/// find it, resume a retained upload, revert the room preview it had
/// claimed and drop the row itself.
extension _MessageFailedRows on ChatMessagesController {
  /// Re-runs the whole upload + send for a media row whose bytes are still
  /// in hand, replacing the failed bubble with a fresh pending one.
  ///
  /// A new optimistic id is minted on purpose. The upload provably never
  /// landed, so there is nothing to be idempotent against, and re-entering
  /// [sendAttachment] / [sendVoice] means the retry inherits the progress
  /// ring, the cancel affordance, the offline queue and the cache
  /// bookkeeping rather than a second, thinner copy of all of it.
  ///
  /// Which is exactly why the old id is taken out of the offline queue
  /// first: the failure that retained these bytes may well have queued
  /// them too, and the retry is about to queue the same file again under
  /// the new id. Leaving both would put the photo in the room twice, under
  /// two idempotency keys the server has no way to relate. The invariant
  /// this keeps is a small one — the queue only ever holds an entry for
  /// the row that is still on screen waiting for it.
  Future<ChatResult<ChatMessage>> _retryRetainedUpload(
    String roomId,
    String messageId,
    RetainedUpload retained,
  ) async {
    // Read off the old row before it goes: how long a voice note runs and
    // the waveform drawn under it live on its metadata and nowhere else,
    // and the caption and the quote were never handed to the registry.
    final recording = _retainedVoiceRecording(roomId, messageId);
    final failedRow = _rowById(retained.roomId, messageId);
    // Released before the retry starts: a retry that fails again retains
    // its own bytes under the new id, and one that succeeds must not leave
    // a copy of the file behind.
    _a._failedUploads.drop(messageId);
    _a.client.cancelOfflineSend(messageId);
    _discardFailedRow(retained.roomId, messageId);
    if (retained.messageType == MessageType.audio) {
      return sendVoice(
        retained.roomId,
        audioBytes: retained.bytes,
        mimeType: retained.mimeType,
        duration: recording.duration,
        waveform: recording.waveform,
        referencedMessageId: failedRow?.referencedMessageId,
      );
    }
    return sendAttachment(
      retained.roomId,
      bytes: retained.bytes,
      mimeType: retained.mimeType,
      fileName: retained.fileName,
      caption: failedRow?.text,
      referencedMessageId: failedRow?.referencedMessageId,
    );
  }

  /// The row [messageId] still on screen in [roomId], or `null` when the
  /// controller is gone (a retry from a chat that was closed in between).
  ChatMessage? _rowById(String roomId, String messageId) {
    final controller = _a._chatControllers[roomId];
    for (final m in controller?.messages ?? const <ChatMessage>[]) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  /// Takes the chat-list preview back off [roomId] when the optimistic row
  /// [messageId] failed and is still the row the list is advertising.
  ///
  /// The fallback is the newest message the room actually holds that is
  /// neither pending nor failed — the last thing that truly went out or
  /// came in. When there is none the preview is cleared rather than left
  /// claiming a send that never happened.
  void _revertRoomPreviewFor(String roomId, String messageId) {
    final controller = _a._chatControllers[roomId];
    ChatMessage? fallback;
    if (controller != null) {
      for (final m in controller.messages) {
        if (m.id == messageId) continue;
        if (controller.isPending(m.id) || controller.isFailed(m.id)) continue;
        if (fallback == null || m.timestamp.isAfter(fallback.timestamp)) {
          fallback = m;
        }
      }
    }
    _a._roomListMutator.revertOptimisticLastMessage(
      roomId,
      messageId,
      fallback: fallback,
    );
  }

  void _discardFailedRow(String roomId, String messageId) {
    _revertRoomPreviewFor(roomId, messageId);
    // `removePending`, not `removeMessage`: the latter takes the bubble out
    // but leaves the id in the controller's pending ledger, so `isFailed`
    // goes on answering true for a row nobody can see — and a second
    // `discardFailed` on it would report success instead of not-found.
    _a._chatControllers[roomId]?.removePending(messageId);
    unawaited(
      _a._cache
              ?.deletePendingMessage(roomId, messageId)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
  }
}
