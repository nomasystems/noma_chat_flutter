import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// A receipt that arrives for a room nobody has open must still leave a
/// trace on disk.
///
/// With no controller there is nothing to advance and nothing to drain, so
/// before this the ✓✓ existed only as the in-memory room-list tick while the
/// cached message rows kept saying ✓ — and those rows are what the next open
/// paints first. The cursor box is where it belongs, because that is what
/// the open path re-reads.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  late MockChatClient client;
  late MemoryChatLocalDatasource cache;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    client.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    cache = MemoryChatLocalDatasource();
    adapter = ChatUiAdapter(client: client, currentUser: me, cache: cache);
    adapter.start();
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'Room1'),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Future<void> drain() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<List<ReadReceipt>> storedCursors() async =>
      (await cache.getReceipts('r1')).dataOrNull ?? const [];

  test('a delivery event with the room closed stores the cursor', () async {
    client.emitEvent(
      const MessageDeliveredEvent(
        roomId: 'r1',
        userId: 'u2',
        messageId: 'm3',
        seq: 3,
      ),
    );
    await drain();

    final stored = await storedCursors();
    expect(stored.length, 1);
    expect(stored.single.userId, 'u2');
    expect(stored.single.lastDeliveredMessageId, 'm3');
    expect(stored.single.lastReadMessageId, isNull);
  });

  test(
    'a read event moves both cursors, a later delivery keeps the read one',
    () async {
      client.emitEvent(
        const ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm2',
          status: ReceiptStatus.read,
          fromUserId: 'u2',
        ),
      );
      await drain();
      var stored = await storedCursors();
      expect(stored.single.lastReadMessageId, 'm2');
      expect(stored.single.lastDeliveredMessageId, 'm2');

      client.emitEvent(
        const MessageDeliveredEvent(
          roomId: 'r1',
          userId: 'u2',
          messageId: 'm4',
          seq: 4,
        ),
      );
      await drain();
      stored = await storedCursors();
      expect(stored.single.lastDeliveredMessageId, 'm4');
      expect(
        stored.single.lastReadMessageId,
        'm2',
        reason: 'a delivery frame says nothing about reading',
      );
    },
  );

  test(
    'nothing is stored for the user\'s own receipts or for a bare sent',
    () async {
      client.emitEvent(
        const ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.read,
          fromUserId: 'u1',
        ),
      );
      client.emitEvent(
        const ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.sent,
          fromUserId: 'u2',
        ),
      );
      await drain();

      expect(await storedCursors(), isEmpty);
    },
  );

  test(
    'an open room keeps writing through the controller, not this path',
    () async {
      adapter.getChatController(
        'r1',
        otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
      );
      client.emitEvent(
        const MessageDeliveredEvent(
          roomId: 'r1',
          userId: 'u2',
          messageId: 'm3',
          seq: 3,
        ),
      );
      await drain();

      expect(
        await storedCursors(),
        isEmpty,
        reason:
            'the controller advanced the rows and the row drain persisted '
            'them; a second, cursor-shaped copy would be a second truth',
      );
    },
  );
}
