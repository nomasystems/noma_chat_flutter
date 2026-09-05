part of 'optimistic_handler.dart';

/// Sending from a draft room, where there is no room id yet: materialising
/// the direct-message room the draft stands for, sending the first message
/// through it and discarding the optimistic row when that first send never
/// lands.
extension _OptimisticDraftSend on OptimisticHandler {
  /// Delegates to the adapter's `ensureDmRoomMaterialized`. Kept as a
  /// thin wrapper so [sendMessage] can read
  /// `controller.draftOtherUserId` without leaking the public API
  /// into this collaborator.
  Future<ChatResult<String>> _materializeDraft(
    ChatController controller,
  ) async {
    final otherUserId = controller.draftOtherUserId;
    if (otherUserId == null) {
      return const ChatFailureResult<String>(
        ValidationFailure(message: 'Draft controller missing draftOtherUserId'),
      );
    }
    return _ensureDmRoomMaterialized(otherUserId);
  }

  /// Fallback for a send whose draft DM could not be materialized into a
  /// real room — typically the device is offline, so `rooms.create` never
  /// reached the server.
  ///
  /// Before this existed the optimistic bubble was only marked failed
  /// in memory: nothing was written to the cache and nothing entered the
  /// offline queue (which is keyed by room id and therefore cannot
  /// represent a message to a DM that has no room yet), so the very first
  /// message of a brand-new DM was lost for good once the screen went
  /// away.
  ///
  /// Two things happen here instead. The optimistic message is persisted
  /// under the draft routing key so it survives leaving the screen, and
  /// the send is re-driven through the contact-addressed DM endpoint,
  /// which enqueues a `PendingSendDirectMessage` carrying the recipient's
  /// user id. That operation resolves — creating it when needed — the 1:1
  /// room server-side when the queue drains after reconnect. The original
  /// optimistic id travels as the idempotency key, so neither the drain
  /// nor a manual retry can duplicate a send that actually landed.
  ///
  /// The fallback is only attempted for failures that prove the request
  /// never reached the server. Anything else (a validation error, a
  /// permission rejection) keeps the plain failed-bubble behaviour rather
  /// than retrying a permanent rejection behind the user's back.
  Future<ChatResult<ChatMessage>> _sendDraftAsDirectMessage({
    required ChatController controller,
    required String draftKey,
    required ChatMessage optimistic,
    required ChatResult<ChatMessage> materializationFailure,
    required OperationKind operationKind,
  }) async {
    final tempId = optimistic.id;
    controller.markFailed(tempId);
    unawaited(
      cache
              ?.savePendingMessage(draftKey, optimistic, isFailed: true)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );

    // Creating the 1:1 room is itself refused with `403 blocked` when the
    // other party blocks this user, and that rejection reached the server
    // — so it must be swallowed here too rather than left as a failed
    // bubble that tells the sender exactly what they must not learn.
    if (_isBlockedError(materializationFailure.failureOrNull)) {
      return swallowDraftBlockedAsSent(
        controller: controller,
        draftKey: draftKey,
        optimistic: optimistic,
        operationKind: operationKind,
      );
    }

    final otherUserId = controller.draftOtherUserId;
    if (otherUserId == null ||
        !_neverReachedServer(materializationFailure.failureOrNull)) {
      return _emitFailure<ChatMessage>(
        materializationFailure,
        operationKind,
        roomId: draftKey,
        messageId: tempId,
      );
    }

    final direct = await client.contacts.sendDirectMessage(
      otherUserId,
      text: optimistic.text,
      messageType: optimistic.messageType,
      referencedMessageId: optimistic.referencedMessageId,
      attachmentUrl: optimistic.attachmentUrl,
      metadata: optimistic.metadata,
      clientMessageId: optimistic.clientMessageId ?? tempId,
    );

    if (direct.isFailure) {
      if (_isBlockedError(direct.failureOrNull)) {
        return swallowDraftBlockedAsSent(
          controller: controller,
          draftKey: draftKey,
          optimistic: optimistic,
          operationKind: operationKind,
        );
      }
      return _emitFailure<ChatMessage>(
        materializationFailure,
        operationKind,
        roomId: draftKey,
        messageId: tempId,
      );
    }

    final sent = _ensureSentReceipt(direct.dataOrThrow);
    if (sent.isProvisional) {
      // Same provisional-echo rule as [sendMessage]: the echo's id does not
      // match the stored message, so the bubble stays pending until the
      // authoritative event reconciles it by clientMessageId.
      controller.markPending(tempId);
    } else {
      controller.confirmSent(tempId, sent);
      unawaited(
        cache
                ?.deletePendingMessage(draftKey, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
    }
    _emitOperationSuccess(operationKind, roomId: draftKey, messageId: tempId);
    return ChatSuccess<ChatMessage>(sent);
  }

  /// Drops the draft-keyed pending row written by a previous
  /// [_sendDraftAsDirectMessage] once the DM owns a real room — the
  /// message now lives under [realRoomId]. No-op when the send never went
  /// through the draft path.
  void _discardDraftPending(
    String draftKey,
    String realRoomId,
    String messageId,
  ) {
    if (draftKey == realRoomId) return;
    unawaited(
      cache
              ?.deletePendingMessage(draftKey, messageId)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
  }
}
