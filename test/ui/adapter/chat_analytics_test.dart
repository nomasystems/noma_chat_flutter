import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Wraps [ChatMessagesApi.send] with a `failSend` toggle. Same shape as
/// `_FailableMessagesApi` in `chat_ui_adapter_f3_test.dart`, trimmed to the
/// one method this file needs.
class _SendFailableMessagesApi implements ChatMessagesApi {
  _SendFailableMessagesApi(this._delegate);
  final ChatMessagesApi _delegate;

  bool failSend = false;

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
    if (failSend) {
      return const ChatFailureResult(ServerFailure(statusCode: 500));
    }
    return _delegate.send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
      tempId: tempId,
      clientMessageId: clientMessageId,
    );
  }

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) =>
      _delegate.get(roomId, messageId);
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
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => _delegate.sendViaWs(
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
  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => _delegate.update(roomId, messageId, text: text, metadata: metadata);
  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) =>
      _delegate.delete(roomId, messageId);
  @override
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _delegate.sendReceipt(roomId, messageId, status: status);
  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) => _delegate.markRoomAsDelivered(
    roomId,
    lastDeliveredMessageId: lastDeliveredMessageId,
  );
  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => _delegate.markRoomAsRead(roomId, lastReadMessageId: lastReadMessageId);
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
  }) => _delegate.getReactions(roomId, messageId, cachePolicy: cachePolicy);
  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) => _delegate.addReaction(roomId, messageId, emoji: emoji);
  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) => _delegate.deleteReaction(roomId, messageId, emoji: emoji);
  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) =>
      _delegate.pinMessage(roomId, messageId);
  @override
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) =>
      _delegate.unpinMessage(roomId, messageId);
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
  @override
  Future<ChatResult<void>> setLocalClearedAt(
    String roomId,
    DateTime clearedAt,
  ) => _delegate.setLocalClearedAt(roomId, clearedAt);
}

class _SendFailableChatClient implements ChatClient {
  _SendFailableChatClient(this._delegate)
    : messages = _SendFailableMessagesApi(_delegate.messages);

  final MockChatClient _delegate;
  @override
  final _SendFailableMessagesApi messages;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _delegate.rooms;
  @override
  ChatMembersApi get members => _delegate.members;
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
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  int get pendingOperationCount => _delegate.pendingOperationCount;
  @override
  Future<void> flushPendingOperations() => _delegate.flushPendingOperations();
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _delegate.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  group('ChatAnalyticsEvent sealed union', () {
    String describeWithWildcard(ChatAnalyticsEvent event) => switch (event) {
      ChatAnalyticsRoomOpened() => 'roomOpened',
      ChatAnalyticsMessageReceived() => 'messageReceived',
      ChatAnalyticsVoicePlayed() => 'voicePlayed',
      // Stands in for a variant added in a future minor release: a
      // wildcard branch keeps consumer code compiling (and correctly
      // routed to a fallback) without listing every current constructor.
      _ => 'unknown',
    };

    test('a switch with a wildcard branch compiles and covers every '
        'variant, including ones it does not name explicitly', () {
      expect(
        describeWithWildcard(
          const ChatAnalyticsEvent.roomOpened(roomId: 'r1', isGroup: false),
        ),
        'roomOpened',
      );
      expect(
        describeWithWildcard(
          const ChatAnalyticsEvent.messageReceived(
            roomId: 'r1',
            messageId: 'm1',
            kind: MessageType.regular,
            isGroup: false,
          ),
        ),
        'messageReceived',
      );
      expect(
        describeWithWildcard(
          const ChatAnalyticsEvent.voicePlayed(
            roomId: 'r1',
            messageId: 'm1',
            durationMs: 1200,
            firstListen: true,
          ),
        ),
        'voicePlayed',
      );
      // Not special-cased above — takes the wildcard branch, the same way
      // a variant this test predates would.
      expect(
        describeWithWildcard(
          const ChatAnalyticsEvent.sendOutcome(
            roomId: 'r1',
            kind: MessageType.regular,
            success: true,
          ),
        ),
        'unknown',
      );
    });
  });

  group('roomOpened', () {
    test('setActiveRoom(roomId) emits roomOpened with isGroup from the '
        'room list', () async {
      final events = <ChatAnalyticsEvent>[];
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: events.add,
      );
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'r1', name: 'Group', isGroup: true),
      );

      adapter.setActiveRoom('r1');

      expect(events, hasLength(1));
      final event = events.single as ChatAnalyticsRoomOpened;
      expect(event.roomId, 'r1');
      expect(event.isGroup, true);

      await adapter.dispose();
      await client.dispose();
    });

    test('a DM draft emits nothing on entry, and the real room emits once '
        'when it materializes', () async {
      final events = <ChatAnalyticsEvent>[];
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: events.add,
      );

      // `draft:<otherUserId>` is a routing key, not a room id: emitting it
      // would put the peer's user id on the analytics channel.
      adapter.setActiveRoom(adapter.dm.draftRoutingKey('u2'));
      expect(events, isEmpty);

      adapter.setActiveRoom('r-real');

      expect(events.whereType<ChatAnalyticsRoomOpened>(), hasLength(1));
      expect(
        events.whereType<ChatAnalyticsRoomOpened>().single.roomId,
        'r-real',
      );

      await adapter.dispose();
      await client.dispose();
    });

    test('setActiveRoom(null) emits nothing', () async {
      final events = <ChatAnalyticsEvent>[];
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: events.add,
      );

      adapter.setActiveRoom('r1');
      events.clear();
      adapter.setActiveRoom(null);

      expect(events, isEmpty);

      await adapter.dispose();
      await client.dispose();
    });
  });

  group('messageReceived', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;
    late List<ChatAnalyticsEvent> events;

    setUp(() {
      client = MockChatClient(currentUserId: 'u1');
      events = <ChatAnalyticsEvent>[];
      adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: events.add,
      );
      adapter.start();
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'r1', name: 'Room1', isGroup: true),
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    test('a message from another user emits messageReceived', () async {
      final msg = ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'hi',
        messageType: MessageType.regular,
      );
      client.emitEvent(NewMessageEvent(message: msg, roomId: 'r1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final received = events.whereType<ChatAnalyticsMessageReceived>();
      expect(received, hasLength(1));
      expect(received.single.roomId, 'r1');
      expect(received.single.messageId, 'm1');
      expect(received.single.kind, MessageType.regular);
      expect(received.single.isGroup, true);
    });

    test('the local echo of a message this device sent does NOT emit '
        'messageReceived', () async {
      final own = ChatMessage(
        id: 'm-own',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'sent by me',
      );
      client.emitEvent(NewMessageEvent(message: own, roomId: 'r1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<ChatAnalyticsMessageReceived>(), isEmpty);
    });
  });

  group('sendOutcome', () {
    test('a successful send emits sendOutcome(success: true)', () async {
      final events = <ChatAnalyticsEvent>[];
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: events.add,
      );

      await adapter.messages.send('r1', text: 'hello');

      final outcomes = events.whereType<ChatAnalyticsSendOutcome>();
      expect(outcomes, hasLength(1));
      expect(outcomes.single.roomId, 'r1');
      expect(outcomes.single.kind, MessageType.regular);
      expect(outcomes.single.success, true);
      expect(outcomes.single.failureKind, isNull);

      await adapter.dispose();
      await client.dispose();
    });

    test('a failed send emits sendOutcome(success: false, failureKind: '
        'the failure class name)', () async {
      final events = <ChatAnalyticsEvent>[];
      final mockClient = MockChatClient(currentUserId: 'u1');
      final failableClient = _SendFailableChatClient(mockClient);
      final adapter = ChatUiAdapter(
        client: failableClient,
        currentUser: currentUser,
        analyticsSink: events.add,
      );

      failableClient.messages.failSend = true;
      await adapter.messages.send('r1', text: 'hello');

      final outcomes = events.whereType<ChatAnalyticsSendOutcome>();
      expect(outcomes, hasLength(1));
      expect(outcomes.single.success, false);
      expect(outcomes.single.failureKind, 'ServerFailure');

      await adapter.dispose();
      await mockClient.dispose();
    });
  });

  group('a throwing sink never breaks the chat', () {
    test(
      'setActiveRoom completes normally when analyticsSink throws',
      () async {
        final client = MockChatClient(currentUserId: 'u1');
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: currentUser,
          analyticsSink: (_) => throw StateError('boom'),
        );

        expect(() => adapter.setActiveRoom('r1'), returnsNormally);
        expect(adapter.activeRoomId, 'r1');

        await adapter.dispose();
        await client.dispose();
      },
    );

    test('sendMessage still succeeds when analyticsSink throws', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        analyticsSink: (_) => throw StateError('boom'),
      );

      final result = await adapter.messages.send('r1', text: 'hello');

      expect(result.isSuccess, true);

      await adapter.dispose();
      await client.dispose();
    });

    test('no sink at all — sending and opening a room never throws', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final adapter = ChatUiAdapter(client: client, currentUser: currentUser);

      expect(() => adapter.setActiveRoom('r1'), returnsNormally);
      final result = await adapter.messages.send('r1', text: 'hello');
      expect(result.isSuccess, true);

      await adapter.dispose();
      await client.dispose();
    });
  });
}
