import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Opening a room whose cached rows say ✓ while the stored cursors say ✓✓
/// must paint ✓✓ on the first frame — not paint ✓ and correct it once the
/// network answers.
///
/// The setup is the reported one: the peer's ✓✓ arrived as an event while
/// the room was closed, so it never reached the cached message rows; it
/// lives in the receipt-cursor box, which is exactly what the open path now
/// reads before it hands the rows to the controller.
///
/// The assertion is per *frame*, not per notification. The hydration
/// deliberately lands in the same synchronous turn as `addMessages`, so a
/// `ChangeNotifier` fires twice but the framework schedules one frame — and
/// a frame is what the user sees. Counting builds is what catches an `await`
/// slipped between the two.
class _CountingClient implements ChatClient {
  _CountingClient(this._delegate)
    : _messages = _CountingMessagesApi(_delegate.messages);

  final ChatClient _delegate;
  final _CountingMessagesApi _messages;

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

  @override
  int cancelOfflineSend(String tempId) => _delegate.cancelOfflineSend(tempId);
}

/// Counts wire reads and can park them, so the test can assert what the UI
/// already shows *while the network has answered nothing at all*.
class _CountingMessagesApi implements ChatMessagesApi {
  _CountingMessagesApi(this._delegate);
  final ChatMessagesApi _delegate;

  int networkListCalls = 0;
  int receiptCalls = 0;
  Completer<void>? networkGate;
  List<ReadReceipt> networkReceipts = const [];

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) async {
    receiptCalls++;
    return ChatSuccess(
      ChatPaginatedResponse(items: networkReceipts, hasMore: false),
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy != CachePolicy.cacheOnly) {
      networkListCalls++;
      final gate = networkGate;
      if (gate != null) await gate.future;
    }
    return _delegate.list(
      roomId,
      pagination: pagination,
      unreadOnly: unreadOnly,
      cachePolicy: cachePolicy,
    );
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      _delegate.getClearedAt(roomId);

  @override
  Future<ChatResult<void>> setLocalClearedAt(
    String roomId,
    DateTime clearedAt,
  ) => _delegate.setLocalClearedAt(roomId, clearedAt);

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

void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const bob = ChatUser(id: 'u2', displayName: 'Bob');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  /// Mock + cache seeded with the reported situation: three of my own
  /// messages cached as `sent`, and a stored cursor from Bob saying he
  /// already got all three.
  ({
    MockChatClient mock,
    _CountingClient client,
    _CountingMessagesApi api,
    MemoryChatLocalDatasource cache,
  })
  seed({List<ReadReceipt> storedCursors = const []}) {
    final mock = MockChatClient(currentUserId: 'u1');
    mock.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    for (var i = 1; i <= 3; i++) {
      mock.addMessage(
        'r1',
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
          receipt: ReceiptStatus.sent,
        ),
      );
    }
    final cache = MemoryChatLocalDatasource();
    if (storedCursors.isNotEmpty) {
      unawaited(cache.saveReceipts('r1', storedCursors));
    }
    final client = _CountingClient(mock);
    return (mock: mock, client: client, api: client._messages, cache: cache);
  }

  testWidgets('no frame shows a single tick when the stored cursor already '
      'says delivered', (tester) async {
    final s = seed(
      storedCursors: [
        ReadReceipt(
          userId: 'u2',
          lastDeliveredMessageId: 'm3',
          lastDeliveredAt: t0.add(const Duration(minutes: 5)),
        ),
      ],
    );
    addTearDown(s.mock.dispose);

    final adapter = ChatUiAdapter(
      client: s.client,
      currentUser: me,
      cache: s.cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1', otherUsers: const [bob]);

    // Park the wire read: whatever the UI shows below owes nothing to it.
    s.api.networkGate = Completer<void>();

    // One entry per BUILD, not per notification: the status the row would
    // paint, resolved the way `MessageList` resolves it
    // (`controller.receiptStatuses[id]` first, the row's own receipt next).
    final painted = <ReceiptStatus?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final m = controller.messages
                .where((msg) => msg.id == 'm1')
                .firstOrNull;
            if (m != null) {
              painted.add(controller.receiptStatuses['m1'] ?? m.receipt);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(painted, isEmpty, reason: 'nothing loaded yet');

    final load = adapter.messages.load('r1');
    // Several frames while the cache phase resolves; none of them may show
    // the single tick.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(painted, isNotEmpty, reason: 'the cached rows painted');
    expect(
      painted,
      everyElement(ReceiptStatus.delivered),
      reason: 'a ✓ frame is the flicker this test exists to catch',
    );
    expect(
      s.api.networkListCalls,
      1,
      reason: 'issued, but parked and unanswered',
    );
    expect(
      s.api.receiptCalls,
      0,
      reason:
          'the wire receipts round trip has '
          'not even started, and the ticks are already right',
    );

    // Let the network finish: it may only confirm, never walk back.
    s.api.networkGate!.complete();
    await load;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(controller.receiptStatuses['m1'], ReceiptStatus.delivered);
    expect(painted, everyElement(ReceiptStatus.delivered));
  });

  testWidgets('a stored cursor never outranks a fresher wire cursor', (
    tester,
  ) async {
    // Disk says delivered up to m3; the server says Bob has READ m2. The
    // read must win where it applies, and delivered must survive on m3.
    final s = seed(
      storedCursors: [
        ReadReceipt(
          userId: 'u2',
          lastDeliveredMessageId: 'm3',
          lastDeliveredAt: t0.add(const Duration(minutes: 5)),
        ),
      ],
    );
    addTearDown(s.mock.dispose);
    s.api.networkReceipts = [
      ReadReceipt(
        userId: 'u2',
        lastReadMessageId: 'm2',
        lastReadAt: t0.add(const Duration(minutes: 9)),
        lastDeliveredMessageId: 'm3',
        lastDeliveredAt: t0.add(const Duration(minutes: 9)),
      ),
    ];

    final adapter = ChatUiAdapter(
      client: s.client,
      currentUser: me,
      cache: s.cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1', otherUsers: const [bob]);
    await adapter.messages.load('r1');
    await tester.pump(const Duration(milliseconds: 20));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m3'], ReceiptStatus.delivered);
  });

  testWidgets('an adapter with no cache behaves exactly as before', (
    tester,
  ) async {
    final s = seed();
    addTearDown(s.mock.dispose);
    final adapter = ChatUiAdapter(client: s.client, currentUser: me);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController('r1', otherUsers: const [bob]);
    final result = await adapter.messages.load('r1');
    await tester.pump(const Duration(milliseconds: 20));

    expect(result.isSuccess, isTrue);
    expect(controller.messages.length, 3);
    expect(controller.receiptStatuses['m1'], isNull);
  });
}
