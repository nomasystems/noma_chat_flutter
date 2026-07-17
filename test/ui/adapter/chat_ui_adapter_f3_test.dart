import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

class _FailableRoomsApi implements ChatRoomsApi {
  final ChatRoomsApi _delegate;
  _FailableRoomsApi(this._delegate);

  bool failMute = false;
  bool failUnmute = false;
  bool failPin = false;
  bool failUnpin = false;

  @override
  Future<ChatResult<RoomPreferences>> patchPreferences(
    String roomId, {
    bool? muted,
    DateTime? muteUntil,
    bool? pinned,
    bool? hidden,
  }) async {
    final mutes = muted == true || muteUntil != null;
    final unmutes = muted == false;
    if (failMute && mutes) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    if (failUnmute && unmutes) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    if (failPin && pinned == true) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    if (failUnpin && pinned == false) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.patchPreferences(
      roomId,
      muted: muted,
      muteUntil: muteUntil,
      pinned: pinned,
      hidden: hidden,
    );
  }

  @override
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
  }) => _delegate.create(
    audience: audience,
    allowInvitations: allowInvitations,
    name: name,
    subject: subject,
    members: members,
    avatarUrl: avatarUrl,
    custom: custom,
    forceGroup: forceGroup,
  );

  @override
  Future<ChatResult<void>> delete(String roomId) => _delegate.delete(roomId);

  @override
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) => _delegate.get(roomId, cachePolicy: cachePolicy);

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) => _delegate.getUserRooms(
    type: type,
    pagination: pagination,
    cachePolicy: cachePolicy,
  );

  @override
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar = false,
    Map<String, dynamic>? custom,
  }) => _delegate.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    clearAvatar: clearAvatar,
    custom: custom,
  );

  @override
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds) =>
      _delegate.batchMarkAsRead(roomIds);

  @override
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      _delegate.batchGetUnread(roomIds);

  @override
  Future<void> updateCachedRoomPreview(
    String roomId, {
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    bool? lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
  }) => _delegate.updateCachedRoomPreview(
    roomId,
    lastMessage: lastMessage,
    lastMessageTime: lastMessageTime,
    lastMessageUserId: lastMessageUserId,
    lastMessageId: lastMessageId,
    lastMessageType: lastMessageType,
    lastMessageMimeType: lastMessageMimeType,
    lastMessageFileName: lastMessageFileName,
    lastMessageDurationMs: lastMessageDurationMs,
    lastMessageIsDeleted: lastMessageIsDeleted,
    lastMessageReactionEmoji: lastMessageReactionEmoji,
  );
}

class _FailableMessagesApi implements ChatMessagesApi {
  final ChatMessagesApi _delegate;
  _FailableMessagesApi(this._delegate);

  bool failUpdate = false;
  bool failDelete = false;
  bool failSend = false;
  bool failAddReaction = false;
  bool failDeleteReaction = false;
  bool failPinMessage = false;
  bool failUnpinMessage = false;

  /// Simulates the backend's ack_mode=async: the 201 echo carries a
  /// server-minted id that does NOT correspond to the stored message.
  bool provisionalSend = false;
  int _provisionalSeq = 0;

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) =>
      _delegate.get(roomId, messageId);

  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    if (failUpdate) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.update(roomId, messageId, text: text, metadata: metadata);
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    if (failDelete) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.delete(roomId, messageId);
  }

  @override
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    String? tempId,
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    if (failSend) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    if (provisionalSend) {
      // ack_mode=async: the 201 echo is minted before persistence and no
      // event fires yet — the authoritative new_message arrives later.
      return ChatSuccess(
        ChatMessage(
          id: 'prov-${_provisionalSeq++}',
          from: 'u1',
          timestamp: DateTime.now(),
          text: text,
          messageType: messageType,
          clientMessageId: clientMessageId,
          isProvisional: true,
        ),
      );
    }
    return _delegate.send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      sourceRoomId: sourceRoomId,
      tempId: tempId,
      metadata: metadata,
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) => _delegate.list(
    roomId,
    pagination: pagination,
    unreadOnly: unreadOnly,
    cachePolicy: cachePolicy,
  );

  @override
  Future<ChatResult<ChatMessage>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => _delegate.sendViaWs(roomId);

  @override
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _delegate.sendReceipt(roomId, messageId, status: status);

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => _delegate.markRoomAsRead(roomId, lastReadMessageId: lastReadMessageId);

  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) => _delegate.markRoomAsDelivered(
    roomId,
    lastDeliveredMessageId: lastDeliveredMessageId,
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) => _delegate.getRoomReceipts(roomId);

  @override
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) => _delegate.sendTyping(roomId, activity: activity);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    ChatCursorPaginationParams? pagination,
  }) => _delegate.getThread(roomId, messageId, pagination: pagination);

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    bool forceRefresh = false,
    CachePolicy? cachePolicy,
  }) => _delegate.getReactions(
    roomId,
    messageId,
    // ignore: deprecated_member_use_from_same_package
    forceRefresh: forceRefresh,
    cachePolicy: cachePolicy,
  );

  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) async {
    if (failAddReaction) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.addReaction(roomId, messageId, emoji: emoji);
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) async {
    if (failDeleteReaction) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.deleteReaction(roomId, messageId, emoji: emoji);
  }

  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) async {
    if (failPinMessage) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.pinMessage(roomId, messageId);
  }

  @override
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) async {
    if (failUnpinMessage) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.unpinMessage(roomId, messageId);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  }) => _delegate.listPins(roomId, pagination: pagination);

  @override
  Future<ChatResult<void>> starMessage(String roomId, String messageId) =>
      _delegate.starMessage(roomId, messageId);

  @override
  Future<ChatResult<void>> unstarMessage(String roomId, String messageId) =>
      _delegate.unstarMessage(roomId, messageId);

  @override
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> listStarred({
    ChatPaginationParams? pagination,
  }) => _delegate.listStarred(pagination: pagination);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    String? roomId,
    ChatPaginationParams? pagination,
  }) => _delegate.search(query, roomId: roomId, pagination: pagination);

  @override
  Future<ChatResult<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  }) => _delegate.report(roomId, messageId, reason: reason);

  @override
  Future<ChatResult<ChatPaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    ChatPaginationParams? pagination,
  }) => _delegate.listReports(roomId, pagination: pagination);

  @override
  Future<ChatResult<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) => _delegate.schedule(
    roomId,
    sendAt: sendAt,
    text: text,
    metadata: metadata,
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  ) => _delegate.listScheduled(roomId);

  @override
  Future<ChatResult<void>> cancelScheduled(String roomId, String scheduledId) =>
      _delegate.cancelScheduled(roomId, scheduledId);

  @override
  Future<ChatResult<void>> clearChat(String roomId) =>
      _delegate.clearChat(roomId);

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      _delegate.getClearedAt(roomId);
}

class _FailableChatClient implements ChatClient {
  final MockChatClient _delegate;
  late final _FailableRoomsApi _failableRooms;
  late final _FailableMessagesApi _failableMessages;

  _FailableChatClient(this._delegate) {
    _failableRooms = _FailableRoomsApi(_delegate.rooms);
    _failableMessages = _FailableMessagesApi(_delegate.messages);
  }

  _FailableRoomsApi get failableRooms => _failableRooms;
  _FailableMessagesApi get failableMessages => _failableMessages;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _failableRooms;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatMessagesApi get messages => _failableMessages;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;
  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
}

void main() {
  late MockChatClient mockClient;
  late _FailableChatClient failableClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    failableClient = _FailableChatClient(mockClient);
    adapter = ChatUiAdapter(client: failableClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('F3.1 optimistic editMessage', () {
    test('updates text locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      final msg = ChatMessage(
        id: 'msg1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'Original',
      );
      controller.addMessage(msg);

      final future = adapter.messages.edit('room1', 'msg1', text: 'Edited');

      expect(controller.messages.first.text, 'Edited');
      await future;
    });

    test('reverts text on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      final msg = ChatMessage(
        id: 'msg1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'Original',
      );
      controller.addMessage(msg);

      failableClient.failableMessages.failUpdate = true;
      final result = await adapter.messages.edit(
        'room1',
        'msg1',
        text: 'Edited',
      );

      expect(result.isFailure, true);
      expect(controller.messages.first.text, 'Original');
    });
  });

  group('F3.1 optimistic deleteMessage', () {
    // WhatsApp-style soft-delete: the deleter's own client keeps the
    // message row but flips it to a tombstone (isDeleted: true, text
    // wiped). Recipients render the same tombstone via the
    // `message_deleted` WS event, so the local view stays consistent.
    test('marks message as deleted locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      final future = adapter.messages.delete('room1', 'msg1');

      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.isDeleted, true);
      expect(controller.messages.first.text, isEmpty);
      await future;
    });

    test('restores original message on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      failableClient.failableMessages.failDelete = true;
      final result = await adapter.messages.delete('room1', 'msg1');

      expect(result.isFailure, true);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.isDeleted, false);
      expect(controller.messages.first.text, 'Hello');
    });
  });

  group('F3.1 optimistic sendReaction', () {
    test('adds reaction locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      final future = adapter.messages.sendReaction(
        'room1',
        messageId: 'msg1',
        emoji: '👍',
      );

      expect(controller.reactions['msg1']?['👍'], 1);
      await future;
    });

    test('removes reaction on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      failableClient.failableMessages.failAddReaction = true;
      final result = await adapter.messages.sendReaction(
        'room1',
        messageId: 'msg1',
        emoji: '👍',
      );

      expect(result.isFailure, true);
      expect(controller.reactions.containsKey('msg1'), false);
    });
  });

  group('F3.1 optimistic muteRoom/unmuteRoom', () {
    test('muteRoom updates muted locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: false),
      );

      final future = adapter.rooms.mute('room1');

      expect(adapter.roomListController.getRoomById('room1')!.muted, true);
      await future;
    });

    test('muteRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: false),
      );

      failableClient.failableRooms.failMute = true;
      final result = await adapter.rooms.mute('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.muted, false);
    });

    test('unmuteRoom updates muted locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: true),
      );

      final future = adapter.rooms.unmute('room1');

      expect(adapter.roomListController.getRoomById('room1')!.muted, false);
      await future;
    });

    test('unmuteRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: true),
      );

      failableClient.failableRooms.failUnmute = true;
      final result = await adapter.rooms.unmute('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.muted, true);
    });
  });

  group('F3.1 optimistic pinRoom/unpinRoom', () {
    test('pinRoom updates pinned locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: false),
      );

      final future = adapter.rooms.pin('room1');

      expect(adapter.roomListController.getRoomById('room1')!.pinned, true);
      await future;
    });

    test('pinRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: false),
      );

      failableClient.failableRooms.failPin = true;
      final result = await adapter.rooms.pin('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.pinned, false);
    });

    test('unpinRoom updates pinned locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: true),
      );

      final future = adapter.rooms.unpin('room1');

      expect(adapter.roomListController.getRoomById('room1')!.pinned, false);
      await future;
    });

    test('unpinRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: true),
      );

      failableClient.failableRooms.failUnpin = true;
      final result = await adapter.rooms.unpin('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.pinned, true);
    });
  });

  group('F3.4 retrySend', () {
    test('retries failed message and confirms on success', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: '_pending_99',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Retry me',
        ),
      );
      controller.markFailed('_pending_99');
      expect(controller.isFailed('_pending_99'), true);

      final result = await adapter.messages.retrySend('room1', '_pending_99');

      expect(result.isSuccess, true);
      final serverMsg = result.dataOrNull!;
      expect(controller.messages.any((m) => m.id == serverMsg.id), true);
      expect(controller.messages.any((m) => m.id == '_pending_99'), false);
    });

    test('returns failure when message not found', () async {
      adapter.getChatController('room1');

      final result = await adapter.messages.retrySend('room1', 'non-existent');

      expect(result.isFailure, true);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('marks failed again on retry failure', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: '_pending_99',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Retry me',
        ),
      );
      controller.markFailed('_pending_99');

      failableClient.failableMessages.failSend = true;
      final result = await adapter.messages.retrySend('room1', '_pending_99');

      expect(result.isFailure, true);
      expect(controller.isFailed('_pending_99'), true);
    });

    test('returns failure when controller not found', () async {
      final result = await adapter.messages.retrySend('no-room', 'msg1');

      expect(result.isFailure, true);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('ack_mode=async provisional send reconciliation', () {
    test('keeps the optimistic bubble pending on a provisional 201 and '
        'confirms it only when the authoritative event arrives', () async {
      await adapter.connect();
      failableClient.failableMessages.provisionalSend = true;
      final controller = adapter.getChatController('room1');

      final result = await adapter.messages.send('room1', text: 'Hello');

      expect(result.isSuccess, isTrue);
      final echoed = result.dataOrNull!;
      expect(echoed.isProvisional, isTrue);
      expect(echoed.clientMessageId, isNotNull);

      // The provisional id must never enter the controller: the bubble is
      // still the optimistic temp row, still pending.
      final tempId = controller.messages.single.id;
      expect(tempId, startsWith('_pending_'));
      expect(controller.isPending(tempId), isTrue);
      expect(controller.messages.any((m) => m.id == echoed.id), isFalse);

      // The authoritative event arrives with the REAL id and the same
      // clientMessageId — it must replace the temp row, not duplicate it.
      mockClient.emitEvent(
        ChatEvent.newMessage(
          roomId: 'room1',
          message: ChatMessage(
            id: 'real-42',
            from: 'u1',
            timestamp: DateTime.now(),
            text: 'Hello',
            clientMessageId: echoed.clientMessageId,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.messages.single.id, 'real-42');
      expect(controller.isPending(tempId), isFalse);
      expect(controller.serverIdForTemp(tempId), 'real-42');
    });
  });

  group('F3.1 optimistic deleteReaction', () {
    test('removes own reaction locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addOwnReaction('msg1', '👍');
      expect(controller.userReactions['msg1']?.contains('👍'), true);

      final future = adapter.messages.deleteReaction(
        'room1',
        messageId: 'msg1',
        emoji: '👍',
      );

      expect(controller.userReactions['msg1']?.contains('👍'), isNot(true));
      await future;
    });

    test('re-adds own reaction on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      controller.addOwnReaction('msg1', '👍');

      failableClient.failableMessages.failDeleteReaction = true;
      final result = await adapter.messages.deleteReaction(
        'room1',
        messageId: 'msg1',
        emoji: '👍',
      );

      expect(result.isFailure, true);
      expect(controller.userReactions['msg1']?.contains('👍'), true);
    });
  });

  group('F3.1 optimistic pinMessage/unpinMessage', () {
    test('pinMessage adds pin locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      expect(controller.isPinned('msg1'), false);

      final future = adapter.messages.pin('room1', 'msg1');

      expect(controller.isPinned('msg1'), true);
      await future;
    });

    test('pinMessage reverts on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      failableClient.failableMessages.failPinMessage = true;

      final result = await adapter.messages.pin('room1', 'msg1');

      expect(result.isFailure, true);
      expect(controller.isPinned('msg1'), false);
    });

    test('pinMessage does not duplicate when already pinned', () async {
      final controller = adapter.getChatController('room1');
      controller.addPin(
        MessagePin(
          roomId: 'room1',
          messageId: 'msg1',
          pinnedBy: 'someone-else',
          pinnedAt: DateTime(2026, 1, 1),
        ),
      );

      await adapter.messages.pin('room1', 'msg1');

      expect(
        controller.pinnedMessages.where((p) => p.messageId == 'msg1').length,
        1,
      );
    });

    test('unpinMessage removes pin locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addPin(
        MessagePin(
          roomId: 'room1',
          messageId: 'msg1',
          pinnedBy: 'u1',
          pinnedAt: DateTime(2026, 1, 1),
        ),
      );

      final future = adapter.messages.unpin('room1', 'msg1');

      expect(controller.isPinned('msg1'), false);
      await future;
    });

    test('unpinMessage restores pin on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      final pin = MessagePin(
        roomId: 'room1',
        messageId: 'msg1',
        pinnedBy: 'u1',
        pinnedAt: DateTime(2026, 1, 1),
      );
      controller.addPin(pin);

      failableClient.failableMessages.failUnpinMessage = true;
      final result = await adapter.messages.unpin('room1', 'msg1');

      expect(result.isFailure, true);
      expect(controller.isPinned('msg1'), true);
    });

    test('loadPins seeds controller state', () async {
      final controller = adapter.getChatController('room1');
      expect(controller.pinnedMessages, isEmpty);

      await adapter.messages.loadPins('room1');

      expect(controller.pinnedMessages, isA<List<MessagePin>>());
    });
  });
}
