import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Cold start with a failed row still in the pending box: what the room
/// open decides about it.
///
/// `ChatUiAdapter._rehydratePendingMessages` resurrects every cached
/// pending row as a failed bubble unless the room already holds the
/// message it stands for. Getting that "already holds" test wrong is not
/// cosmetic: the pending row carries a `clientMessageId`, so re-adding it
/// does not paint a second bubble — it lands *on* the delivered message
/// and repaints it as failed.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const peer = ChatUser(id: 'u2', displayName: 'Bob');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  /// Opens `r1` over [cache] with [serverMessages] already stored
  /// server-side, and returns the controller once the room open — and the
  /// rehydration pass it ends with — has settled.
  Future<ChatController> openRoom(
    MemoryChatLocalDatasource cache,
    List<ChatMessage> serverMessages,
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
    for (final m in serverMessages) {
      client.addMessage('r1', m);
    }

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
    return controller;
  }

  test(
    'a delivered attachment is not repainted as failed by its own row',
    () async {
      final cache = MemoryChatLocalDatasource();
      addTearDown(cache.dispose);

      /// Exactly the row `sendAttachment` caches when the send fails after
      /// the upload landed: no `text` at all, plus the idempotency key it
      /// put on the wire.
      final ghost = ChatMessage(
        id: '_pending_1',
        from: 'u1',
        timestamp: t0,
        messageType: MessageType.attachment,
        clientMessageId: '_pending_1',
        attachmentUrl: 'https://cdn.example/blob',
        mimeType: 'image/png',
      );
      await cache.savePendingMessage('r1', ghost, isFailed: true);

      /// The server did receive it. Its echo carries `text: ''` — which is
      /// what the text heuristic compares against the row's `null` and
      /// calls a mismatch — and the same key, which is proof it landed.
      final delivered = ChatMessage(
        id: 'srv-1',
        from: 'u1',
        timestamp: t0.add(const Duration(seconds: 2)),
        text: '',
        messageType: MessageType.attachment,
        clientMessageId: '_pending_1',
        attachmentUrl: 'https://cdn.example/blob',
        mimeType: 'image/png',
        receipt: ReceiptStatus.delivered,
      );

      final controller = await openRoom(cache, [delivered]);

      expect(controller.messages.map((m) => m.id), [
        'srv-1',
      ], reason: 'the pending row must not replace the authoritative message');
      expect(controller.isFailed('srv-1'), isFalse);
      expect(controller.isFailed('_pending_1'), isFalse);
      expect(
        (await cache.getPendingMessages('r1')).dataOrThrow,
        isEmpty,
        reason: 'a superseded row is dropped so it cannot come back',
      );
    },
  );

  test('a keyless row still matches on text', () async {
    final cache = MemoryChatLocalDatasource();
    addTearDown(cache.dispose);

    final ghost = ChatMessage(
      id: 'temp-legacy',
      from: 'u1',
      timestamp: t0,
      text: 'the send that landed',
    );
    await cache.savePendingMessage('r1', ghost, isFailed: true);

    final delivered = ChatMessage(
      id: 'srv-2',
      from: 'u1',
      timestamp: t0.add(const Duration(seconds: 5)),
      text: 'the send that landed',
    );

    final controller = await openRoom(cache, [delivered]);

    expect(controller.messages.map((m) => m.id), [
      'srv-2',
    ], reason: 'with no key on either side the old heuristic is all there is');
    expect((await cache.getPendingMessages('r1')).dataOrThrow, isEmpty);
  });

  test('two sends of the same text are told apart by their keys', () async {
    final cache = MemoryChatLocalDatasource();
    addTearDown(cache.dispose);

    /// The user typed "ok", the send failed, and they typed "ok" again —
    /// a second send under a second key. The first one never reached the
    /// server and must survive the reload as a retriable failed bubble.
    final ghost = ChatMessage(
      id: 'temp-a',
      from: 'u1',
      timestamp: t0,
      text: 'ok',
      clientMessageId: 'temp-a',
    );
    await cache.savePendingMessage('r1', ghost, isFailed: true);

    final delivered = ChatMessage(
      id: 'srv-3',
      from: 'u1',
      timestamp: t0.add(const Duration(seconds: 5)),
      text: 'ok',
      clientMessageId: 'temp-b',
    );

    final controller = await openRoom(cache, [delivered]);

    expect(
      controller.messages.map((m) => m.id),
      containsAll(['srv-3', 'temp-a']),
      reason: 'distinct keys are proof of two distinct sends',
    );
    expect(controller.isFailed('temp-a'), isTrue);
    expect(controller.isFailed('srv-3'), isFalse);
    expect(
      (await cache.getPendingMessages(
        'r1',
      )).dataOrThrow.map((p) => p.message.id),
      ['temp-a'],
    );
  });
}
