part of 'chat_ui_adapter.dart';

/// Holds the implementations of the adapter's optimistic-UI mutating
/// operations. Each method follows the same pattern: paint the optimistic
/// state, call the SDK, on success persist + finalise, on failure roll back.
///
/// Lives as a `part of` collaborator to read the adapter's private state
/// (`_chatControllers`, `_cache`, `_pendingReactionDeletes`, …) without an
/// explicit dependency-injection surface.
class _OptimisticHandler {
  _OptimisticHandler(this._adapter);

  final ChatUiAdapter _adapter;

  Future<Result<ChatMessage>> sendMessage(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    OperationKind? operationKind,
  }) async {
    final controller = _adapter._chatControllers[roomId];
    final tempId = '_pending_${DateTime.now().microsecondsSinceEpoch}';

    final optimistic = ChatMessage(
      id: tempId,
      from: _adapter.currentUser.id,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      attachmentUrl: attachmentUrl,
      mimeType: metadata?['mimeType'] as String?,
      fileName: metadata?['fileName'] as String?,
      metadata: metadata,
    );

    if (controller != null) {
      controller.addMessage(optimistic);
      controller.markPending(tempId);
    }

    unawaited(
      _adapter._cache?.savePendingMessage(roomId, optimistic).catchError((_) {}) ??
          Future.value(),
    );

    _adapter._updateRoomLastMessage(roomId, optimistic);

    final result = await _adapter.client.messages.send(
      roomId,
      text: text,
      referencedMessageId: referencedMessageId,
      messageType: messageType,
      metadata: metadata,
      attachmentUrl: attachmentUrl,
      tempId: tempId,
    );

    final confirmed =
        result.isSuccess ? _adapter._ensureSentReceipt(result.dataOrNull!) : null;
    if (controller != null) {
      if (confirmed != null) {
        controller.confirmSent(tempId, confirmed);
      } else {
        controller.markFailed(tempId);
      }
    }

    if (confirmed != null) {
      unawaited(
        _adapter._cache?.deletePendingMessage(roomId, tempId).catchError((_) {}) ??
            Future.value(),
      );
      _adapter._updateRoomLastMessage(roomId, confirmed);
    } else if (_adapter._isBlockedError(result.failureOrNull)) {
      unawaited(
        _adapter._cache?.deletePendingMessage(roomId, tempId).catchError((_) {}) ??
            Future.value(),
      );
      _adapter.roomListController.removeRoom(roomId);
      _adapter.removeChatController(roomId);
    } else {
      unawaited(
        _adapter._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError((_) {}) ??
            Future.value(),
      );
    }

    return _adapter._emitFailure(
      result,
      operationKind ?? OperationKind.sendMessage,
      roomId: roomId,
      messageId: tempId,
    );
  }

  Future<Result<void>> editMessage(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final controller = _adapter._chatControllers[roomId];
    final originalMessage =
        controller?.messages.where((m) => m.id == messageId).firstOrNull;

    if (controller != null && originalMessage != null) {
      controller.updateMessage(originalMessage.copyWith(text: text));
    }

    final result = await _adapter.client.messages.update(
      roomId,
      messageId,
      text: text,
      metadata: metadata,
    );

    if (result.isFailure && controller != null && originalMessage != null) {
      controller.updateMessage(originalMessage);
    }

    return _adapter._emitFailure(
      result,
      OperationKind.editMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<void>> deleteMessage(String roomId, String messageId) async {
    final controller = _adapter._chatControllers[roomId];
    final originalMessage =
        controller?.messages.where((m) => m.id == messageId).firstOrNull;

    if (controller != null && originalMessage != null) {
      controller.removeMessage(messageId);
    }

    final result = await _adapter.client.messages.delete(roomId, messageId);

    if (result.isFailure && controller != null && originalMessage != null) {
      controller.addMessage(originalMessage);
    }

    return _adapter._emitFailure(
      result,
      OperationKind.deleteMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    final controller = _adapter._chatControllers[roomId];
    controller?.addOwnReaction(messageId, emoji);

    final result = await _adapter.client.messages.send(
      roomId,
      messageType: MessageType.reaction,
      reaction: emoji,
      referencedMessageId: messageId,
    );

    if (result.isFailure) {
      controller?.removeOwnReaction(messageId, emoji);
    } else {
      _adapter._updateRoomReactionPreview(
        roomId,
        emoji,
        _adapter.currentUser.id,
        messageId,
      );
    }

    return _adapter._emitFailure(
      result,
      OperationKind.sendReaction,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    final controller = _adapter._chatControllers[roomId];
    controller?.removeOwnReaction(messageId, emoji);
    _adapter._pendingReactionDeletes.add(messageId);

    final result =
        await _adapter.client.messages.deleteReaction(roomId, messageId);

    _adapter._pendingReactionDeletes.remove(messageId);
    if (result.isFailure) {
      controller?.addOwnReaction(messageId, emoji);
    }

    return _adapter._emitFailure(
      result,
      OperationKind.deleteReaction,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<ChatMessage>> retrySend(String roomId, String messageId) async {
    final controller = _adapter._chatControllers[roomId];
    if (controller == null) {
      return const Failure(NotFoundFailure('Controller not found'));
    }

    final message =
        controller.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null) {
      return const Failure(NotFoundFailure('Message not found'));
    }

    controller.markPending(messageId);
    unawaited(
      _adapter._cache?.savePendingMessage(roomId, message).catchError((_) {}) ??
          Future.value(),
    );

    final result = await _adapter.client.messages.send(
      roomId,
      text: message.text,
      messageType: message.messageType,
      referencedMessageId: message.referencedMessageId,
      attachmentUrl: message.attachmentUrl,
      metadata: message.metadata,
      tempId: messageId,
    );

    if (result.isSuccess) {
      controller.confirmSent(
        messageId,
        _adapter._ensureSentReceipt(result.dataOrNull!),
      );
      unawaited(
        _adapter._cache
                ?.deletePendingMessage(roomId, messageId)
                .catchError((_) {}) ??
            Future.value(),
      );
    } else {
      controller.markFailed(messageId);
      unawaited(
        _adapter._cache
                ?.savePendingMessage(roomId, message, isFailed: true)
                .catchError((_) {}) ??
            Future.value(),
      );
    }

    return _adapter._emitFailure(
      result,
      OperationKind.retrySend,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<void>> pinMessage(String roomId, String messageId) async {
    final controller = _adapter._chatControllers[roomId];
    final wasAlreadyPinned = controller?.isPinned(messageId) ?? false;
    if (controller != null && !wasAlreadyPinned) {
      controller.addPin(
        MessagePin(
          roomId: roomId,
          messageId: messageId,
          pinnedBy: _adapter.currentUser.id,
          pinnedAt: DateTime.now(),
        ),
      );
    }

    final result =
        await _adapter.client.messages.pinMessage(roomId, messageId);

    if (result.isFailure && controller != null && !wasAlreadyPinned) {
      controller.removePin(messageId);
    }
    return _adapter._emitFailure(
      result,
      OperationKind.pinMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }

  Future<Result<void>> unpinMessage(String roomId, String messageId) async {
    final controller = _adapter._chatControllers[roomId];
    final existing = controller?.pinnedMessages
        .where((p) => p.messageId == messageId)
        .firstOrNull;
    if (controller != null && existing != null) {
      controller.removePin(messageId);
    }

    final result =
        await _adapter.client.messages.unpinMessage(roomId, messageId);

    if (result.isFailure && controller != null && existing != null) {
      controller.addPin(existing);
    }
    return _adapter._emitFailure(
      result,
      OperationKind.unpinMessage,
      roomId: roomId,
      messageId: messageId,
    );
  }
}
