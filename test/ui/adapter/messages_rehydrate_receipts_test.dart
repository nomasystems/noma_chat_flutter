import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Wraps a [ChatClient] but routes `messages.getRoomReceipts` to a
/// canned receipts list. The rest delegates to the mock unchanged.
class _ReceiptsClient implements ChatClient {
  _ReceiptsClient(this._delegate, List<ReadReceipt> receipts)
    : _messages = _ReceiptsMessagesApi(_delegate.messages, receipts);

  final ChatClient _delegate;
  final _ReceiptsMessagesApi _messages;

  @override
  ChatMessagesApi get messages => _messages;

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
    String? referencedMessageId,
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
    referencedMessageId: referencedMessageId,
  );

  @override
  int cancelOfflineSend(String tempId) => _delegate.cancelOfflineSend(tempId);
}

class _ReceiptsMessagesApi implements ChatMessagesApi {
  _ReceiptsMessagesApi(this._delegate, this.receipts);
  final ChatMessagesApi _delegate;
  final List<ReadReceipt> receipts;

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) async =>
      ChatSuccess(ChatPaginatedResponse(items: receipts, hasMore: false));

  // Methods exercised by `messages.load` delegate explicitly; the rest
  // of the contract is satisfied by noSuchMethod (unused in this test).
  // getClearedAt must be explicit (not via noSuchMethod): the wrapped
  // MockMessagesApi declares it concretely, so it cannot be reached
  // through noSuchMethod forwarding.
  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      _delegate.getClearedAt(roomId);

  @override
  Future<ChatResult<void>> setLocalClearedAt(
    String roomId,
    DateTime clearedAt,
  ) => _delegate.setLocalClearedAt(roomId, clearedAt);

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
  dynamic noSuchMethod(Invocation invocation) =>
      (_delegate as dynamic).noSuchMethod(invocation);
}

/// In-memory cache whose first [getMessages] hands control to [onFirstRead]
/// before answering. The rehydration reads it to place a read cursor that
/// paginated out of the window, so this is a real suspension point in the
/// middle of the marking loop — where a WS frame lands in production.
class _GatedCache extends MemoryChatLocalDatasource {
  Future<void> Function()? onFirstRead;
  bool gateFired = false;

  @override
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
  }) async {
    final gate = onFirstRead;
    if (gate != null) {
      onFirstRead = null;
      gateFired = true;
      await gate();
    }
    return super.getMessages(roomId, limit: limit);
  }
}

void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  test('load() rehydrates delivered cursors and reads by messageId order, '
      'not by timestamp', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    for (var i = 1; i <= 3; i++) {
      mockClient.addMessage(
        'r1',
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
      );
    }

    // u2's row: read cursor on m1, delivered cursor on m2. The
    // lastReadAt timestamp is LATER than every message — the legacy
    // timestamp comparison would over-mark all three as read; the
    // messageId-order semantics must mark only m1.
    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u2',
        lastReadMessageId: 'm1',
        lastReadAt: t0.add(const Duration(hours: 1)),
        lastDeliveredMessageId: 'm2',
        lastDeliveredAt: t0.add(const Duration(hours: 1)),
      ),
    ]);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    final result = await adapter.messages.load('r1');
    expect(result.isSuccess, isTrue);
    // The rehydration runs fire-and-forget after load resolves.
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.delivered);
    expect(controller.receiptStatuses['m3'], isNull);
  });

  test('load() marks nothing when an out-of-window read cursor cannot be '
      'resolved, instead of reading lastReadAt as a message time', () async {
    // Bob is offline while Alice sends m1..m5. He opens the room at 14:00
    // and his client confirms up to m1, so the server stores
    // `lastReadMessageId: m1, lastReadAt: 14:00` — the wall clock of the
    // CONFIRMATION, hours after the message it confirms. Alice re-opens on
    // a window where m1 has paginated out. m2..m5 are all timestamped
    // before 14:00 and none of them was read: comparing against
    // `lastReadAt` would flip all four to ✓✓ and, receipts being
    // monotonic, the delivered cursor below could never take it back.
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    for (var i = 2; i <= 5; i++) {
      mockClient.addMessage(
        'r1',
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
      );
    }

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u2',
        lastReadMessageId: 'm1',
        lastReadAt: t0.add(const Duration(hours: 4)),
        lastDeliveredMessageId: 'm5',
        lastDeliveredAt: t0.add(const Duration(hours: 4)),
      ),
    ]);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    for (var i = 2; i <= 5; i++) {
      expect(
        controller.receiptStatuses['m$i'],
        ReceiptStatus.delivered,
        reason: 'm$i was delivered to Bob but never read by him',
      );
    }
  });

  test('load() resolves an out-of-window read cursor from the local cache '
      'and marks by the cursor message own timestamp', () async {
    // The cursor message (m4) is not in the window — locally hidden, or
    // simply never loaded on this device — but the cache still holds its
    // row. Its OWN timestamp is a legitimate cutoff: unlike lastReadAt, it
    // is the time of a message the peer demonstrably read. m5 sits after
    // it in the window and stays unmarked, which is what tells the cutoff
    // apart from the confirmation time (4 hours later, past everything).
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    final all = [
      for (var i = 1; i <= 5; i++)
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
    ];
    for (final m in all.where((m) => m.id != 'm4')) {
      mockClient.addMessage('r1', m);
    }

    final cache = MemoryChatLocalDatasource();
    addTearDown(cache.dispose);
    await cache.saveMessages('r1', all);

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u2',
        lastReadMessageId: 'm4',
        lastReadAt: t0.add(const Duration(hours: 4)),
      ),
    ]);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      cache: cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m3'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m5'], isNull);

    // Cursor-derived marks are the ones that earn a cache write.
    final stored = (await cache.getMessages('r1')).dataOrThrow;
    final byId = {for (final m in stored) m.id: m};
    expect(byId['m1']?.receipt, ReceiptStatus.read);
    expect(byId['m3']?.receipt, ReceiptStatus.read);
    expect(byId['m5']?.receipt, isNull);
  });

  test('load() applies a whole-room read (no cursor id) in memory but never '
      'writes it to the cache', () async {
    // `lastReadMessageId: null` is what the backend stores for a whole-room
    // read, and the confirmation time is then the only description of the
    // cursor's extent. The mark is shown, but it is not written to the
    // cache: a stored receipt is permanent, and this one cannot be
    // re-checked against a cursor on the next cold start.
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    final all = [
      for (var i = 1; i <= 2; i++)
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
    ];
    for (final m in all) {
      mockClient.addMessage('r1', m);
    }

    final cache = MemoryChatLocalDatasource();
    addTearDown(cache.dispose);
    await cache.saveMessages('r1', all);

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(userId: 'u2', lastReadAt: t0.add(const Duration(hours: 1))),
    ]);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      cache: cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.read);

    final stored = (await cache.getMessages('r1')).dataOrThrow;
    expect(
      stored.map((m) => m.receipt),
      everyElement(isNull),
      reason: 'a mark with no cursor behind it must not become permanent',
    );
  });

  test('a receipt frame landing mid-rehydration cannot persist a whole-room '
      'mark the rehydration held back', () async {
    // Same invariant as the test above, under the interleaving that used to
    // defeat it. u2's whole-room read marks m1 and m2 in memory; u3's read
    // cursor sits outside the window, so resolving it needs a cache read.
    // A `read_receipt` frame arriving in that window reaches the same
    // write-back queue from the event router, which knows nothing about what
    // the rehydration decided to hold back.
    //
    // The suspension moved: the cursor timestamps are resolved up front so
    // the marking loop itself can be synchronous, which is what lets a room
    // open with its ticks already right. So a frame can no longer land
    // *between* two marks — it lands before them. The invariant is unchanged
    // and is the controller's, not the drain's: a mark with no cursor behind
    // it is held back whoever drains the queue. A `delivered` frame that
    // genuinely arrived is a different thing and persists on its own merits.
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2', 'u3'],
      ),
    );
    final window = [
      for (var i = 1; i <= 2; i++)
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
    ];
    for (final m in window) {
      mockClient.addMessage('r1', m);
    }
    // Older than the window and cached only: u3's cursor resolves to it, so
    // u3 marks nothing here — the row exists to make the loop read the cache.
    final paginatedOut = ChatMessage(
      id: 'm0',
      from: 'u1',
      timestamp: t0.subtract(const Duration(hours: 1)),
      text: 'm0',
    );

    final cache = _GatedCache();
    addTearDown(cache.dispose);
    await cache.saveMessages('r1', [paginatedOut, ...window]);

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(userId: 'u2', lastReadAt: t0.add(const Duration(hours: 1))),
      ReadReceipt(
        userId: 'u3',
        lastReadMessageId: 'm0',
        lastReadAt: t0.add(const Duration(hours: 1)),
      ),
    ]);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      cache: cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    cache.onFirstRead = () async {
      mockClient.emitEvent(
        const ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.delivered,
          fromUserId: 'u2',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    };

    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      cache.gateFired,
      isTrue,
      reason: 'the rehydration must have suspended on the cache read',
    );
    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.read);

    final stored = (await cache.getMessages('r1')).dataOrThrow;
    expect(
      stored.map((m) => m.receipt),
      isNot(contains(ReceiptStatus.read)),
      reason:
          'a mark with no cursor behind it must not become permanent, '
          'whichever consumer drains the queue',
    );
    expect(
      stored.firstWhere((m) => m.id == 'm2').receipt,
      isNull,
      reason:
          'm2 was marked read by the whole-room cursor alone and by '
          'nothing else, so nothing about it may reach disk',
    );
  });

  test('load() does not drop a receipt when the network row carries '
      'none', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    final m1 = ChatMessage(
      id: 'm1',
      from: 'u1',
      timestamp: t0.add(const Duration(minutes: 1)),
      text: 'm1',
    );
    mockClient.addMessage('r1', m1);

    final client = _ReceiptsClient(mockClient, const []);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    controller.addMessages([m1]);
    controller.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
    expect(controller.messages.single.receipt, ReceiptStatus.read);

    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.messages.single.receipt, ReceiptStatus.read);
  });

  test('load() re-derives the self-chat mark from the user\'s own read '
      'cursor, the one no session writes to the cache', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Notes',
        audience: RoomAudience.contacts,
        members: ['u1'],
      ),
    );
    mockClient.addMessage(
      'r1',
      ChatMessage(
        id: 'm1',
        from: 'u1',
        timestamp: t0.add(const Duration(minutes: 1)),
        text: 'm1',
      ),
    );

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u1',
        lastReadMessageId: 'm1',
        lastReadAt: t0.add(const Duration(hours: 1)),
      ),
    ]);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1');
    // What the room row reports; no member list is ever fetched, which is
    // how a host with `hydrateGroupMembers: false` opens every room.
    controller.setMemberCount(1);

    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
  });

  test('load() resolves an out-of-window self-chat cursor from the cache '
      'and still writes nothing back', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Notes',
        audience: RoomAudience.contacts,
        members: ['u1'],
      ),
    );
    final all = [
      for (var i = 1; i <= 5; i++)
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
    ];
    for (final m in all.where((m) => m.id != 'm4')) {
      mockClient.addMessage('r1', m);
    }

    final cache = MemoryChatLocalDatasource();
    addTearDown(cache.dispose);
    await cache.saveMessages('r1', all);

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u1',
        lastReadMessageId: 'm4',
        lastReadAt: t0.add(const Duration(hours: 4)),
      ),
    ]);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      cache: cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1');
    controller.setMemberCount(1);

    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m3'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m5'], isNull);

    final stored = (await cache.getMessages('r1')).dataOrThrow;
    expect(
      stored.map((m) => m.receipt),
      isNot(contains(ReceiptStatus.read)),
      reason:
          'the mark rests on an empty room, the one piece of evidence a '
          'later hydration can contradict',
    );
  });

  test('load() still drops the own read cursor in a room that has a '
      'peer', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    mockClient.addMessage(
      'r1',
      ChatMessage(
        id: 'm1',
        from: 'u1',
        timestamp: t0.add(const Duration(minutes: 1)),
        text: 'm1',
      ),
    );

    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u1',
        lastReadMessageId: 'm1',
        lastReadAt: t0.add(const Duration(hours: 1)),
      ),
    ]);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1');
    controller.setMemberCount(2);

    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], isNull);
  });
}
