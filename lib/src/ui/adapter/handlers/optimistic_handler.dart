import 'dart:async';

import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../models/message.dart';
import '../../../models/pin.dart';
import '../../../models/user.dart';
import '../../../observability/chat_logger.dart';
import '../../controller/chat_controller.dart';
import '../../controller/room_list_controller.dart';
import '../operation_error.dart';
import '../services/chat_controller_registry.dart';
import '../services/pending_reactions_registry.dart';

/// Optimistic-UI mutating operations the adapter exposes publicly
/// (`sendMessage`, `editMessage`, `deleteMessage`, `sendReaction`,
/// `deleteReaction`, `retrySend`, `pinMessage`, `unpinMessage`,
/// `starMessage`, `unstarMessage`).
/// Each method follows the same pattern: paint the optimistic state,
/// call the SDK, on success persist + finalise, on failure roll back.
///
/// Dependencies are injected explicitly so the handler is unit-testable
/// without instantiating the adapter.
class OptimisticHandler {
  OptimisticHandler({
    required this.client,
    required this.controllers,
    required this.roomList,
    required this.pendingReactions,
    required ChatUser Function() currentUser,
    required this.cache,
    required Future<ChatResult<String>> Function(String otherUserId)
    ensureDmRoomMaterialized,
    required void Function(String roomId, ChatMessage message)
    updateRoomLastMessage,
    required void Function(
      String roomId,
      String reaction,
      String userId,
      String messageId,
    )
    updateRoomReactionPreview,
    required ChatMessage Function(ChatMessage message) ensureSentReceipt,
    required bool Function(ChatFailure? failure) isBlockedError,
    required bool Function(ChatFailure? failure) isMutedError,
    void Function(String roomId)? onModerationLock,
    required ChatResult<T> Function<T>(
      ChatResult<T> result,
      OperationKind kind, {
      String? roomId,
      String? messageId,
      String? userId,
    })
    emitFailure,
    required void Function(
      OperationKind kind, {
      String? roomId,
      String? messageId,
      String? userId,
    })
    emitOperationSuccess,
    required ChatResult<void> Function(Object _) swallowCacheThrow,
    ChatLogger? logs,
  }) : _currentUser = currentUser,
       _ensureDmRoomMaterialized = ensureDmRoomMaterialized,
       _updateRoomLastMessage = updateRoomLastMessage,
       _updateRoomReactionPreview = updateRoomReactionPreview,
       _ensureSentReceipt = ensureSentReceipt,
       _isBlockedError = isBlockedError,
       _isMutedError = isMutedError,
       _onModerationLock = onModerationLock,
       _emitFailure = emitFailure,
       _emitOperationSuccess = emitOperationSuccess,
       _swallowCacheThrow = swallowCacheThrow,
       _logs = logs;

  final ChatClient client;
  final ChatControllerRegistry controllers;
  final RoomListController roomList;
  final PendingReactionsRegistry pendingReactions;
  final ChatLocalDatasource? cache;
  final ChatLogger? _logs;

  final ChatUser Function() _currentUser;
  final Future<ChatResult<String>> Function(String otherUserId)
  _ensureDmRoomMaterialized;
  final void Function(String roomId, ChatMessage message)
  _updateRoomLastMessage;
  final void Function(
    String roomId,
    String reaction,
    String userId,
    String messageId,
  )
  _updateRoomReactionPreview;
  final ChatMessage Function(ChatMessage message) _ensureSentReceipt;
  final bool Function(ChatFailure? failure) _isBlockedError;
  final bool Function(ChatFailure? failure) _isMutedError;

  /// Invoked with the room id when a send is rejected with a 403 "muted".
  /// The adapter wires this to a room-detail refresh so `selfMuted` flips
  /// and the composer swaps to the read-only "an admin muted you" banner
  /// — covering the race where the user was muted with the chat open.
  final void Function(String roomId)? _onModerationLock;
  final ChatResult<T> Function<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  })
  _emitFailure;
  final void Function(
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  })
  _emitOperationSuccess;
  final ChatResult<void> Function(Object _) _swallowCacheThrow;

  Future<ChatResult<ChatMessage>> sendMessage(
    String roomIdOrDraftKey, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    String? attachmentId,
    OperationKind? operationKind,
  }) async {
    final controller = controllers[roomIdOrDraftKey];
    final tempId = '_pending_${DateTime.now().microsecondsSinceEpoch}';

    final optimistic = ChatMessage(
      id: tempId,
      from: _currentUser().id,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      // The optimistic temp id doubles as the server idempotency key: it
      // uniquely identifies this logical message, is reused on every
      // offline-queue retry, and is echoed back on the persisted message
      // so a POST that actually landed before failing is never duplicated.
      clientMessageId: tempId,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      mimeType: metadata?['mimeType'] as String?,
      fileName: metadata?['fileName'] as String?,
      metadata: metadata,
    );

    if (controller != null) {
      controller.addMessage(optimistic);
      controller.markPending(tempId);
    }

    // Materialize the draft DM into a real room before the actual send.
    // ChatFailureResult here aborts the send and marks the optimistic message as
    // failed — no orphan room left on the server, no broken state in the
    // controller. The user can retry from the failed bubble.
    String effectiveRoomId;
    if (controller != null && controller.isDraft) {
      final materialization = await _materializeDraft(controller);
      if (materialization.isFailure) {
        controller.markFailed(tempId);
        return _emitFailure<ChatMessage>(
          materialization.castFailure<ChatMessage>(),
          operationKind ?? OperationKind.sendMessage,
          roomId: roomIdOrDraftKey,
          messageId: tempId,
        );
      }
      effectiveRoomId = materialization.dataOrThrow;
    } else {
      effectiveRoomId = roomIdOrDraftKey;
    }

    unawaited(
      cache
              ?.savePendingMessage(effectiveRoomId, optimistic)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );

    _updateRoomLastMessage(effectiveRoomId, optimistic);

    final result = await client.messages.send(
      effectiveRoomId,
      text: text,
      referencedMessageId: referencedMessageId,
      messageType: messageType,
      metadata: metadata,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      tempId: tempId,
      clientMessageId: tempId,
    );

    // 403 "blocked" on send is swallowed (WhatsApp parity): a blocked
    // sender sees NOTHING. The backend rejects delivery in both
    // directions once either party blocks the other, but the sender must
    // not be able to tell — no failed bubble, no error toast, the chat
    // stays put. We mark the optimistic message as SENT locally (it will
    // never be delivered, but the sender keeps typing into the void) and
    // early-return success so the failure never reaches `_emitFailure`.
    // The "I am the blocker → drop the row" pruning that used to live
    // here is gone: blocking keeps the room (handled elsewhere).
    if (result.isFailure && _isBlockedError(result.failureOrNull)) {
      final sent = _ensureSentReceipt(optimistic);
      if (controller != null) {
        controller.confirmSent(tempId, sent);
      }
      unawaited(
        cache
                ?.deletePendingMessage(effectiveRoomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _updateRoomLastMessage(effectiveRoomId, sent);
      return ChatSuccess<ChatMessage>(sent);
    }

    final logs = _logs;
    if (logs != null) {
      if (result.isSuccess) {
        logs.message(
          ChatLogLevel.debug,
          'sendMessage confirmed: ${logs.content(text)}',
          fields: {'roomId': effectiveRoomId, 'tempId': tempId},
        );
      } else {
        logs.message(
          ChatLogLevel.warn,
          'sendMessage failed: ${result.failureOrNull}',
          fields: {'roomId': effectiveRoomId, 'tempId': tempId},
        );
      }
    }

    final confirmed = result.isSuccess
        ? _ensureSentReceipt(result.dataOrThrow)
        : null;
    if (controller != null) {
      if (confirmed != null) {
        // An ack_mode=async provisional echo carries an id that does NOT
        // match the stored message, so confirming with it would strand the
        // bubble under a dead id. Keep the optimistic row pending instead;
        // the authoritative `new_message` event replaces it (and clears
        // the pending mark) via the clientMessageId reconciliation in
        // ChatController.addMessage.
        if (!confirmed.isProvisional) {
          controller.confirmSent(tempId, confirmed);
        }
      } else {
        controller.markFailed(tempId);
      }
    }

    if (confirmed != null) {
      unawaited(
        cache
                ?.deletePendingMessage(effectiveRoomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _updateRoomLastMessage(effectiveRoomId, confirmed);
    } else {
      unawaited(
        cache
                ?.savePendingMessage(
                  effectiveRoomId,
                  optimistic,
                  isFailed: true,
                )
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      // 403 "muted": the user was muted by an admin (possibly while this
      // chat was open). Re-fetch the room so `selfMuted` flips and the
      // composer locks behind the read-only banner — the user gets a clear
      // reason instead of a mystery failed bubble they keep retrying.
      if (_isMutedError(result.failureOrNull)) {
        _onModerationLock?.call(effectiveRoomId);
      }
    }

    return _emitFailure<ChatMessage>(
      result,
      operationKind ?? OperationKind.sendMessage,
      roomId: effectiveRoomId,
      messageId: tempId,
    );
  }

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

  Future<ChatResult<void>> editMessage(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final controller = controllers[roomId];
    final originalMessage = controller?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;

    if (controller != null && originalMessage != null) {
      // Also flip `isEdited` so the WhatsApp-style "edited" badge appears
      // immediately on the sender's own bubble. Without it, the badge only
      // showed up later when the backend's `message_updated` event came
      // back via WS and triggered `_refreshMessage` from REST — that ~100-
      // 500ms gap is visible enough to look broken to the user.
      controller.updateMessage(
        originalMessage.copyWith(text: text, isEdited: true),
      );
    }

    final result = await client.messages.update(
      roomId,
      messageId,
      text: text,
      metadata: metadata,
    );

    if (result.isFailure && controller != null && originalMessage != null) {
      controller.updateMessage(originalMessage);
    }

    return _emitFailure<void>(
      result,
      OperationKind.editMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> deleteMessage(
    String roomId,
    String messageId,
  ) async {
    final controller = controllers[roomId];
    final originalMessage = controller?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;

    // WhatsApp-style: the deleter's own client KEEPS the message in
    // the list but flips it to a tombstone (`isDeleted: true`, text
    // wiped). The bubble's existing render picks "You deleted this
    // message" for outgoing tombstones. Previously the message was
    // removed from the list, which left the deleter without any
    // visible trace — inconsistent with every recipient (who marks
    // the same row via the `message_deleted` WS event) and with
    // WhatsApp. On failure we restore the original via
    // `updateMessage` (the row never left the list, so addMessage
    // would have duplicated it).
    if (controller != null && originalMessage != null) {
      controller.updateMessage(
        originalMessage.copyWith(isDeleted: true, text: ''),
      );
    }

    final result = await client.messages.delete(roomId, messageId);

    if (result.isFailure && controller != null && originalMessage != null) {
      controller.updateMessage(originalMessage);
    }
    if (result.isSuccess) {
      _emitOperationSuccess(
        OperationKind.deleteMessage,
        roomId: roomId,
        messageId: messageId,
      );
    }

    return _emitFailure<void>(
      result,
      OperationKind.deleteMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  /// Removes the local rendering of [messageId] from [roomId] without
  /// touching the server. WhatsApp's "Delete for me" — the deleter
  /// (or any client) can hide a tombstone from their own chat view
  /// once the global delete has landed. The message stays deleted
  /// for everyone else.
  ///
  /// Distinct from [deleteMessage] (which soft-deletes globally).
  /// Safe to call on non-deleted messages too if the consumer wants
  /// to implement plain "hide for me" without a global delete — but
  /// the example UI only exposes this option after the tombstone.
  Future<ChatResult<void>> deleteMessageLocally(
    String roomId,
    String messageId,
  ) async {
    final controller = controllers[roomId];
    controller?.removeMessage(messageId);
    // Drop from the local cache so the row doesn't pop back on the
    // next room re-open from a cache hit.
    cache?.deleteMessage(roomId, messageId);
    // ALSO persist a "hide for me" marker keyed by `messageId`. Without
    // this the next Phase 2 network fetch in `messages.load` would
    // bring the tombstone back (the backend has no per-user hide
    // state). The cached layer's `list` filter consumes this set so
    // the row stays gone across chat re-open and app restart. Safe to
    // call when `cache` is null — that just means the consumer opted
    // out of persistence and accepts the row reappearing on restart.
    unawaited(
      (cache?.hideMessageLocally(roomId, messageId) ??
              Future.value(const ChatSuccess<void>(null)))
          .catchError(
            (_) => const ChatFailureResult<void>(
              UnexpectedFailure('hideMessageLocally failed'),
            ),
          ),
    );
    _emitOperationSuccess(
      OperationKind.deleteMessage,
      roomId: roomId,
      messageId: messageId,
    );
    return const ChatSuccess<void>(null);
  }

  Future<ChatResult<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    final controller = controllers[roomId];
    controller?.addOwnReaction(messageId, emoji);

    // Canonical reactions endpoint: a reaction is a sub-resource of the
    // message, not a synthetic reaction-typed message. This keeps the
    // timeline and the offline send queue clean.
    final result = await client.messages.addReaction(
      roomId,
      messageId,
      emoji: emoji,
    );

    if (result.isFailure) {
      controller?.removeOwnReaction(messageId, emoji);
    } else {
      _updateRoomReactionPreview(roomId, emoji, _currentUser().id, messageId);
    }

    return _emitFailure<void>(
      result,
      OperationKind.sendReaction,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    final controller = controllers[roomId];
    controller?.removeOwnReaction(messageId, emoji);
    pendingReactions.markPendingDelete(messageId);

    final result = await client.messages.deleteReaction(
      roomId,
      messageId,
      emoji: emoji,
    );

    pendingReactions.unmarkPendingDelete(messageId);
    if (result.isFailure) {
      controller?.addOwnReaction(messageId, emoji);
    }

    return _emitFailure<void>(
      result,
      OperationKind.deleteReaction,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<ChatMessage>> retrySend(
    String roomId,
    String messageId,
  ) async {
    final controller = controllers[roomId];
    if (controller == null) {
      return const ChatFailureResult(NotFoundFailure('Controller not found'));
    }

    final message = controller.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    if (message == null) {
      return const ChatFailureResult(NotFoundFailure('Message not found'));
    }

    controller.markPending(messageId);
    unawaited(
      cache
              ?.savePendingMessage(roomId, message)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );

    final result = await client.messages.send(
      roomId,
      text: message.text,
      messageType: message.messageType,
      referencedMessageId: message.referencedMessageId,
      attachmentUrl: message.attachmentUrl,
      attachmentId: message.attachmentId,
      metadata: message.metadata,
      tempId: messageId,
      // Reuse the original optimistic id as the idempotency key so a manual
      // retry of a send that actually landed (lost response) returns the
      // existing message instead of creating a duplicate.
      clientMessageId: messageId,
    );

    if (result.isSuccess) {
      final confirmed = _ensureSentReceipt(result.dataOrThrow);
      // Same provisional-echo rule as sendMessage: keep the bubble pending
      // until the authoritative event reconciles by clientMessageId.
      if (!confirmed.isProvisional) {
        controller.confirmSent(messageId, confirmed);
      }
      unawaited(
        cache
                ?.deletePendingMessage(roomId, messageId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
    } else {
      controller.markFailed(messageId);
      unawaited(
        cache
                ?.savePendingMessage(roomId, message, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
    }

    return _emitFailure<ChatMessage>(
      result,
      OperationKind.retrySend,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> pinMessage(String roomId, String messageId) async {
    final controller = controllers[roomId];
    final wasAlreadyPinned = controller?.isPinned(messageId) ?? false;
    if (controller != null && !wasAlreadyPinned) {
      controller.addPin(
        MessagePin(
          roomId: roomId,
          messageId: messageId,
          pinnedBy: _currentUser().id,
          pinnedAt: DateTime.now(),
        ),
      );
    }

    final result = await client.messages.pinMessage(roomId, messageId);

    if (result.isFailure && controller != null && !wasAlreadyPinned) {
      controller.removePin(messageId);
    }
    if (result.isSuccess && !wasAlreadyPinned) {
      _emitOperationSuccess(
        OperationKind.pinMessage,
        roomId: roomId,
        messageId: messageId,
      );
    }
    return _emitFailure<void>(
      result,
      OperationKind.pinMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) async {
    final controller = controllers[roomId];
    final existing = controller?.pinnedMessages
        .where((p) => p.messageId == messageId)
        .firstOrNull;
    if (controller != null && existing != null) {
      controller.removePin(messageId);
    }

    final result = await client.messages.unpinMessage(roomId, messageId);

    if (result.isFailure && controller != null && existing != null) {
      controller.addPin(existing);
    }
    if (result.isSuccess) {
      _emitOperationSuccess(
        OperationKind.unpinMessage,
        roomId: roomId,
        messageId: messageId,
      );
    }
    return _emitFailure<void>(
      result,
      OperationKind.unpinMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> starMessage(String roomId, String messageId) async {
    final controller = controllers[roomId];
    final message = controller?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    final wasStarred = message?.isStarred ?? false;
    if (controller != null && !wasStarred) {
      controller.setMessageStarred(messageId, true);
    }

    final result = await client.messages.starMessage(roomId, messageId);

    if (result.isFailure && controller != null && !wasStarred) {
      controller.setMessageStarred(messageId, false);
    }
    if (result.isSuccess) {
      _emitOperationSuccess(
        OperationKind.starMessage,
        roomId: roomId,
        messageId: messageId,
      );
    }
    return _emitFailure<void>(
      result,
      OperationKind.starMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<ChatResult<void>> unstarMessage(
    String roomId,
    String messageId,
  ) async {
    final controller = controllers[roomId];
    final message = controller?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    final wasStarred = message?.isStarred ?? false;
    if (controller != null && wasStarred) {
      controller.setMessageStarred(messageId, false);
    }

    final result = await client.messages.unstarMessage(roomId, messageId);

    if (result.isFailure && controller != null && wasStarred) {
      controller.setMessageStarred(messageId, true);
    }
    if (result.isSuccess) {
      _emitOperationSuccess(
        OperationKind.unstarMessage,
        roomId: roomId,
        messageId: messageId,
      );
    }
    return _emitFailure<void>(
      result,
      OperationKind.unstarMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }
}
