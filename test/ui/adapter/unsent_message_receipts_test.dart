import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// End-to-end: a send the user watched fail must stay out of the message
/// history.
///
/// The pending box is scratch space — [ChatUiAdapter] re-reads it on every
/// room open and drops rows from it once a send confirms. The message box
/// is history, and it is permanent: `messageToMap` merges receipts upward
/// and never lowers one. The receipt write-back
/// (`ChatEventRouter._persistReceipts` and its counterpart in
/// `ChatMessagesController`) is the only path that ever put an optimistic
/// row into the second box, and it did so marked read.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const peer = ChatUser(id: 'u2', displayName: 'Bob');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  final ghost = ChatMessage(
    id: 'temp-1',
    from: 'u1',
    timestamp: t0,
    text: 'the send that failed',
    clientMessageId: 'temp-1',
  );

  /// An adapter over [cache] with `r1` seeded server-side with one real
  /// outgoing message an hour after [ghost], and [ghost] itself sitting in
  /// the pending box as a failed send. Returns the opened controller.
  Future<(MockChatClient, ChatUiAdapter, ChatController)> openRoom(
    MemoryChatLocalDatasource cache,
  ) async {
    final client = MockChatClient(currentUserId: 'u1');
    addTearDown(client.dispose);
    client.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    client.addMessage(
      'r1',
      ChatMessage(
        id: 'm1',
        from: 'u1',
        timestamp: t0.add(const Duration(hours: 1)),
        text: 'the send that landed',
      ),
    );
    await cache.savePendingMessage('r1', ghost, isFailed: true);

    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      cache: cache,
    );
    addTearDown(adapter.dispose);
    adapter.start();
    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [peer],
    );
    expect((await adapter.messages.load('r1')).isSuccess, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      controller.isFailed('temp-1'),
      isTrue,
      reason: 'the room open must surface the pending row as failed',
    );
    return (client, adapter, controller);
  }

  test(
    'a peer read never puts a failed row into the message history',
    () async {
      final cache = MemoryChatLocalDatasource();
      addTearDown(cache.dispose);
      final (client, _, controller) = await openRoom(cache);

      client.emitEvent(
        const ChatEvent.receiptUpdated(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.read,
          fromUserId: 'u2',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
      expect(controller.receiptStatuses['temp-1'], isNull);
      expect(controller.getMessageById('temp-1')?.receipt, isNull);

      final stored = (await cache.getMessages('r1')).dataOrThrow;
      // m1 proves the write-back ran at all, so temp-1's absence is a
      // decision and not a missing round trip.
      expect(
        stored.where((m) => m.id == 'm1').single.receipt,
        ReceiptStatus.read,
      );
      expect(
        stored.map((m) => m.id),
        isNot(contains('temp-1')),
        reason: 'a message the server never accepted is not history',
      );
    },
  );

  test(
    'a retried send leaves one row in the message history, not two',
    () async {
      final cache = MemoryChatLocalDatasource();
      addTearDown(cache.dispose);
      final (client, adapter, controller) = await openRoom(cache);

      client.emitEvent(
        const ChatEvent.receiptUpdated(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.read,
          fromUserId: 'u2',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        (await adapter.messages.retrySend('r1', 'temp-1')).isSuccess,
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        controller.messages.where((m) => m.text == ghost.text),
        hasLength(1),
      );
      expect((await cache.getPendingMessages('r1')).dataOrThrow, isEmpty);

      // What a cold start renders from the local boxes: nothing ever deletes
      // the ghost's history row, so if the fan-out wrote one the retried
      // message appears twice — once under the temporary id, once under the
      // server's.
      final stored = (await cache.getMessages('r1')).dataOrThrow;
      final reopened = ChatController(
        initialMessages: stored,
        currentUser: me,
        otherUsers: const [peer],
      );
      addTearDown(reopened.dispose);
      expect(
        reopened.messages.where((m) => m.text == ghost.text),
        hasLength(1),
      );
    },
  );
}
