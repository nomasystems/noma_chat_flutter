import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _FailableRoomsApi implements ChatRoomsApi {
  final ChatRoomsApi _delegate;
  _FailableRoomsApi(this._delegate);

  bool failMute = false;
  bool failUnmute = false;
  bool failPin = false;
  bool failUnpin = false;

  @override
  Future<Result<void>> mute(String roomId) async {
    if (failMute) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.mute(roomId);
  }

  @override
  Future<Result<void>> unmute(String roomId) async {
    if (failUnmute) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.unmute(roomId);
  }

  @override
  Future<Result<void>> pin(String roomId) async {
    if (failPin) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.pin(roomId);
  }

  @override
  Future<Result<void>> unpin(String roomId) async {
    if (failUnpin) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.unpin(roomId);
  }

  @override
  Future<Result<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => _delegate.create(
    audience: audience,
    allowInvitations: allowInvitations,
    name: name,
    subject: subject,
    members: members,
    avatarUrl: avatarUrl,
    custom: custom,
  );

  @override
  Future<Result<void>> delete(String roomId) => _delegate.delete(roomId);

  @override
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    PaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<Result<RoomDetail>> get(String roomId, {CachePolicy? cachePolicy}) =>
      _delegate.get(roomId, cachePolicy: cachePolicy);

  @override
  Future<Result<UserRooms>> getUserRooms({
    String type = 'all',
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) => _delegate.getUserRooms(
    type: type,
    pagination: pagination,
    cachePolicy: cachePolicy,
  );

  @override
  Future<Result<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => _delegate.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    custom: custom,
  );

  @override
  Future<Result<void>> batchMarkAsRead(List<String> roomIds) =>
      _delegate.batchMarkAsRead(roomIds);

  @override
  Future<Result<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      _delegate.batchGetUnread(roomIds);

  @override
  Future<Result<void>> hide(String roomId) => _delegate.hide(roomId);

  @override
  Future<Result<void>> unhide(String roomId) => _delegate.unhide(roomId);

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
  bool failDeleteReaction = false;
  bool failPinMessage = false;
  bool failUnpinMessage = false;

  @override
  Future<Result<ChatMessage>> get(String roomId, String messageId) =>
      _delegate.get(roomId, messageId);

  @override
  Future<Result<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    if (failUpdate) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.update(roomId, messageId, text: text, metadata: metadata);
  }

  @override
  Future<Result<void>> delete(String roomId, String messageId) async {
    if (failDelete) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.delete(roomId, messageId);
  }

  @override
  Future<Result<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    String? tempId,
    Map<String, dynamic>? metadata,
  }) async {
    if (failSend) return const Failure(ServerFailure(statusCode: 500));
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
  Future<Result<PaginatedResponse<ChatMessage>>> list(
    String roomId, {
    CursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) => _delegate.list(
    roomId,
    pagination: pagination,
    unreadOnly: unreadOnly,
    cachePolicy: cachePolicy,
  );

  @override
  Future<Result<void>> sendViaWs(
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
  Future<Result<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _delegate.sendReceipt(roomId, messageId, status: status);

  @override
  Future<Result<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => _delegate.markRoomAsRead(roomId, lastReadMessageId: lastReadMessageId);

  @override
  Future<Result<PaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) => _delegate.getRoomReceipts(roomId);

  @override
  Future<Result<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) => _delegate.sendTyping(roomId, activity: activity);

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    CursorPaginationParams? pagination,
  }) => _delegate.getThread(roomId, messageId, pagination: pagination);

  @override
  Future<Result<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    bool forceRefresh = false,
  }) => _delegate.getReactions(roomId, messageId, forceRefresh: forceRefresh);

  @override
  Future<Result<void>> deleteReaction(String roomId, String messageId) async {
    if (failDeleteReaction) {
      return const Failure(ServerFailure(statusCode: 500));
    }
    return _delegate.deleteReaction(roomId, messageId);
  }

  @override
  Future<Result<void>> pinMessage(String roomId, String messageId) async {
    if (failPinMessage) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.pinMessage(roomId, messageId);
  }

  @override
  Future<Result<void>> unpinMessage(String roomId, String messageId) async {
    if (failUnpinMessage) return const Failure(ServerFailure(statusCode: 500));
    return _delegate.unpinMessage(roomId, messageId);
  }

  @override
  Future<Result<PaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    PaginationParams? pagination,
  }) => _delegate.listPins(roomId, pagination: pagination);

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    PaginationParams? pagination,
  }) => _delegate.search(query, roomId: roomId, pagination: pagination);

  @override
  Future<Result<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  }) => _delegate.report(roomId, messageId, reason: reason);

  @override
  Future<Result<PaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    PaginationParams? pagination,
  }) => _delegate.listReports(roomId, pagination: pagination);

  @override
  Future<Result<ScheduledMessage>> schedule(
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
  Future<Result<PaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  ) => _delegate.listScheduled(roomId);

  @override
  Future<Result<void>> cancelScheduled(String roomId, String scheduledId) =>
      _delegate.cancelScheduled(roomId, scheduledId);

  @override
  Future<Result<void>> clearChat(String roomId) => _delegate.clearChat(roomId);

  @override
  Future<DateTime?> getClearedAt(String roomId) =>
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
}

void main() {
  late MockChatClient mockClient;
  late _FailableChatClient failableClient;
  late ChatUiAdapter adapter;

  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

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

      final future = adapter.editMessage('room1', 'msg1', text: 'Edited');

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
      final result = await adapter.editMessage('room1', 'msg1', text: 'Edited');

      expect(result.isFailure, true);
      expect(controller.messages.first.text, 'Original');
    });
  });

  group('F3.1 optimistic deleteMessage', () {
    test('removes message locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      final future = adapter.deleteMessage('room1', 'msg1');

      expect(controller.messages, isEmpty);
      await future;
    });

    test('re-adds message on SDK failure', () async {
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
      final result = await adapter.deleteMessage('room1', 'msg1');

      expect(result.isFailure, true);
      expect(controller.messages, hasLength(1));
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

      final future = adapter.sendReaction(
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

      failableClient.failableMessages.failSend = true;
      final result = await adapter.sendReaction(
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

      final future = adapter.muteRoom('room1');

      expect(adapter.roomListController.getRoomById('room1')!.muted, true);
      await future;
    });

    test('muteRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: false),
      );

      failableClient.failableRooms.failMute = true;
      final result = await adapter.muteRoom('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.muted, false);
    });

    test('unmuteRoom updates muted locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: true),
      );

      final future = adapter.unmuteRoom('room1');

      expect(adapter.roomListController.getRoomById('room1')!.muted, false);
      await future;
    });

    test('unmuteRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', muted: true),
      );

      failableClient.failableRooms.failUnmute = true;
      final result = await adapter.unmuteRoom('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.muted, true);
    });
  });

  group('F3.1 optimistic pinRoom/unpinRoom', () {
    test('pinRoom updates pinned locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: false),
      );

      final future = adapter.pinRoom('room1');

      expect(adapter.roomListController.getRoomById('room1')!.pinned, true);
      await future;
    });

    test('pinRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: false),
      );

      failableClient.failableRooms.failPin = true;
      final result = await adapter.pinRoom('room1');

      expect(result.isFailure, true);
      expect(adapter.roomListController.getRoomById('room1')!.pinned, false);
    });

    test('unpinRoom updates pinned locally before SDK response', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: true),
      );

      final future = adapter.unpinRoom('room1');

      expect(adapter.roomListController.getRoomById('room1')!.pinned, false);
      await future;
    });

    test('unpinRoom reverts on SDK failure', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test', pinned: true),
      );

      failableClient.failableRooms.failUnpin = true;
      final result = await adapter.unpinRoom('room1');

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

      final result = await adapter.retrySend('room1', '_pending_99');

      expect(result.isSuccess, true);
      final serverMsg = result.dataOrNull!;
      expect(controller.messages.any((m) => m.id == serverMsg.id), true);
      expect(controller.messages.any((m) => m.id == '_pending_99'), false);
    });

    test('returns failure when message not found', () async {
      adapter.getChatController('room1');

      final result = await adapter.retrySend('room1', 'non-existent');

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
      final result = await adapter.retrySend('room1', '_pending_99');

      expect(result.isFailure, true);
      expect(controller.isFailed('_pending_99'), true);
    });

    test('returns failure when controller not found', () async {
      final result = await adapter.retrySend('no-room', 'msg1');

      expect(result.isFailure, true);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('F3.1 optimistic deleteReaction', () {
    test('removes own reaction locally before SDK response', () async {
      final controller = adapter.getChatController('room1');
      controller.addOwnReaction('msg1', '👍');
      expect(controller.userReactions['msg1']?.contains('👍'), true);

      final future = adapter.deleteReaction(
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
      final result = await adapter.deleteReaction(
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

      final future = adapter.pinMessage('room1', 'msg1');

      expect(controller.isPinned('msg1'), true);
      await future;
    });

    test('pinMessage reverts on SDK failure', () async {
      final controller = adapter.getChatController('room1');
      failableClient.failableMessages.failPinMessage = true;

      final result = await adapter.pinMessage('room1', 'msg1');

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

      await adapter.pinMessage('room1', 'msg1');

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

      final future = adapter.unpinMessage('room1', 'msg1');

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
      final result = await adapter.unpinMessage('room1', 'msg1');

      expect(result.isFailure, true);
      expect(controller.isPinned('msg1'), true);
    });

    test('loadPins seeds controller state', () async {
      final controller = adapter.getChatController('room1');
      expect(controller.pinnedMessages, isEmpty);

      await adapter.loadPins('room1');

      expect(controller.pinnedMessages, isA<List<MessagePin>>());
    });
  });
}
