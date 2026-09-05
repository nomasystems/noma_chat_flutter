part of 'mock_chat_client.dart';

class MockMessagesApi implements ChatMessagesApi {
  final MockChatClient _client;
  MockMessagesApi(this._client);

  /// When `true`, the next [list] call made with
  /// `cachePolicy: CachePolicy.networkOnly` *throws* (rather than returning
  /// a failed [ChatResult]), then resets to `false`. Lets tests exercise the
  /// "an awaited call inside a flow threw" path — e.g. `ChatUiAdapter.resync`
  /// reverting its debounce seal on an exception, not just on `isFailure`.
  bool throwNextList = false;

  /// When set, the next [send] call fails with this failure and leaves the
  /// room untouched, then resets to `null`. Lets tests drive the send
  /// paths' rejection branches — a `403 {"detail":"blocked"}` above all,
  /// which every send path swallows as a locally sent message.
  ChatFailure? failNextSendWith;

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) async {
    final messages = _client._messages[roomId] ?? [];
    final msg = messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return const ChatFailureResult(NotFoundFailure());
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) async {
    final forced = failNextSendWith;
    if (forced != null) {
      failNextSendWith = null;
      return ChatFailureResult(forced);
    }
    final msg = ChatMessage(
      id: _client._nextMessageId(),
      from: _client.currentUserId,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      clientMessageId: clientMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      metadata: metadata,
    );
    _client._messages.putIfAbsent(roomId, () => []);
    _client._messages[roomId]!.insert(0, msg);
    if (messageType == MessageType.reaction && reaction != null) {
      _client.emitEvent(
        ChatEvent.reactionAdded(
          roomId: roomId,
          messageId: referencedMessageId ?? msg.id,
          userId: msg.from,
          reaction: reaction,
        ),
      );
    } else {
      _client.emitEvent(ChatEvent.newMessage(message: msg, roomId: roomId));
    }
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    if (throwNextList && cachePolicy == CachePolicy.networkOnly) {
      throwNextList = false;
      throw StateError('mock messages.list failure');
    }
    final messages = _client._messages[roomId] ?? [];
    return ChatSuccess(ChatPaginatedResponse(items: messages, hasMore: false));
  }

  @override
  Future<ChatResult<ChatMessage>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => send(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    attachmentId: attachmentId,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
  );

  /// When set, the next [update] call fails with this failure and leaves
  /// the store untouched, then clears itself. Lets a test drive the paths
  /// that only one specific server refusal reaches — an edit turned down
  /// with `EditWindowExpiredFailure` behaves nothing like an edit that hit
  /// a flaky network.
  ChatFailure? failNextUpdateWith;

  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final forced = failNextUpdateWith;
    if (forced != null) {
      failNextUpdateWith = null;
      return ChatFailureResult(forced);
    }
    final messages = _client._messages[roomId];
    if (messages == null) return const ChatFailureResult(NotFoundFailure());
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return const ChatFailureResult(NotFoundFailure());
    messages[idx] = messages[idx].copyWith(text: text, metadata: metadata);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    _client._messages[roomId]?.removeWhere((m) => m.id == messageId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) async => const ChatSuccess(null);

  /// Records each `markRoomAsRead` invocation as a `(roomId,
  /// lastReadMessageId)` tuple so tests can assert how often the
  /// adapter flushed read receipts and against which high-water
  /// mark. Cleared via [resetMarkRoomAsReadCalls].
  final List<({String roomId, String? lastReadMessageId})> markRoomAsReadCalls =
      [];

  /// Clears the [markRoomAsReadCalls] history. Convenient at the
  /// start of a test stage that wants to isolate a specific flush.
  void resetMarkRoomAsReadCalls() => markRoomAsReadCalls.clear();

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    markRoomAsReadCalls.add((
      roomId: roomId,
      lastReadMessageId: lastReadMessageId,
    ));
    return const ChatSuccess(null);
  }

  /// Records each `markRoomAsDelivered` invocation as a `(roomId,
  /// lastDeliveredMessageId)` tuple so tests can assert how the adapter
  /// confirms delivery and with which cursor.
  final List<({String roomId, String lastDeliveredMessageId})>
  markRoomAsDeliveredCalls = [];

  /// Clears the [markRoomAsDeliveredCalls] history.
  void resetMarkRoomAsDeliveredCalls() => markRoomAsDeliveredCalls.clear();

  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) async {
    markRoomAsDeliveredCalls.add((
      roomId: roomId,
      lastDeliveredMessageId: lastDeliveredMessageId,
    ));
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    ChatCursorPaginationParams? pagination,
  }) async {
    final messages = _client._messages[roomId] ?? [];
    final thread = messages.where((m) => m.id == messageId).toList();
    return ChatSuccess(ChatPaginatedResponse(items: thread, hasMore: false));
  }

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    @Deprecated(
      'Use cachePolicy: CachePolicy.networkOnly instead. '
      'forceRefresh will be removed in 1.0.',
    )
    bool forceRefresh = false,
    CachePolicy? cachePolicy,
  }) async => const ChatSuccess([]);

  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) async {
    _client.emitEvent(
      ChatEvent.reactionAdded(
        roomId: roomId,
        messageId: messageId,
        userId: _client.currentUserId,
        reaction: emoji,
      ),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unpinMessage(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> starMessage(String roomId, String messageId) async {
    _client._starred[messageId] = roomId;
    _client.emitEvent(
      ChatEvent.messageUpdated(roomId: roomId, messageId: messageId),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> unstarMessage(
    String roomId,
    String messageId,
  ) async {
    _client._starred.remove(messageId);
    _client.emitEvent(
      ChatEvent.messageUpdated(roomId: roomId, messageId: messageId),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> listStarred({
    ChatPaginationParams? pagination,
  }) async {
    final entries = _client._starred.entries.toList().reversed;
    final items = [
      for (final e in entries)
        StarredMessage(
          userId: _client.currentUserId,
          messageId: e.key,
          roomId: e.value,
          starredAt: DateTime.now(),
          preview: _client._starredPreview(e.value, e.key),
        ),
    ];
    return ChatSuccess(
      ChatPaginatedResponse(
        items: items,
        hasMore: false,
        totalCount: items.length,
      ),
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    String? roomId,
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) async => ChatSuccess(
    ScheduledMessage(
      id: 'mock-scheduled-1',
      userId: _client.currentUserId,
      roomId: roomId,
      sendAt: sendAt,
      createdAt: DateTime.now(),
      text: text,
      metadata: metadata,
    ),
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  ) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> cancelScheduled(
    String roomId,
    String scheduledId,
  ) async => const ChatSuccess(null);

  final Map<String, DateTime> _clearedAt = {};

  /// When `true`, [getClearedAt] fails instead of answering. Twin of
  /// [MockRoomsApi.failDeletedRoomIdsRead] for the clear cutoff: an
  /// unreadable cutoff is NOT the same as "never cleared", and treating it
  /// as such repaints every cleared row with its old preview and badge.
  bool failClearedAtRead = false;

  @override
  Future<ChatResult<void>> clearChat(String roomId) async {
    _clearedAt[roomId] = DateTime.now().toUtc();
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) async =>
      failClearedAtRead
      ? const ChatFailureResult(UnexpectedFailure('store read failed'))
      : ChatSuccess(_clearedAt[roomId]);

  @override
  Future<ChatResult<void>> setLocalClearedAt(
    String roomId,
    DateTime clearedAt,
  ) async {
    _clearedAt[roomId] = clearedAt;
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveLocalMessage(
    String roomId,
    ChatMessage message,
  ) async {
    final messages = _client._messages.putIfAbsent(roomId, () => []);
    final existing = messages.indexWhere((m) => m.id == message.id);
    if (existing >= 0) {
      messages[existing] = message;
    } else {
      messages.insert(0, message);
    }
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> hideLocalMessage(
    String roomId,
    String messageId,
  ) async {
    _client._messages[roomId]?.removeWhere((m) => m.id == messageId);
    return const ChatSuccess(null);
  }
}
