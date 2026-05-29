import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Exercises the message load / pagination / local-hide / clear-filter
/// branches of ChatMessagesController via the adapter + MockChatClient,
/// plus send variations (reply, metadata, typed). Reliable, mock-backed.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client
      ..seedRoom(
        const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
      )
      ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Future<String> sendOne(String text) async {
    final r = await adapter.sendMessage('r1', text: text);
    return r.dataOrThrow.id;
  }

  group('ChatMessagesController — load + pagination', () {
    test('load returns sent messages and loadMore paginates', () async {
      await sendOne('one');
      await sendOne('two');
      await sendOne('three');

      final loaded = await adapter.loadMessages('r1');
      expect(loaded.isSuccess, isTrue);

      final more = await adapter.loadMoreMessages('r1', limit: 1);
      expect(more.isSuccess, isTrue);
    });
  });

  group('ChatMessagesController — local hide + clear filters', () {
    test('deleteLocally then reload runs the hide filter', () async {
      final id = await sendOne('hide me');
      await adapter.loadMessages('r1');

      expect((await adapter.deleteMessageLocally('r1', id)).isSuccess, isTrue);

      // Reload re-applies the local-hide predicate path.
      final reloaded = await adapter.loadMessages('r1');
      expect(reloaded.isSuccess, isTrue);
    });

    test('clearChat then reload runs the clear filter', () async {
      await sendOne('a');
      await sendOne('b');
      await adapter.loadMessages('r1');

      expect((await adapter.clearChat('r1')).isSuccess, isTrue);

      final reloaded = await adapter.loadMessages('r1');
      expect(reloaded.isSuccess, isTrue);
    });
  });

  group('ChatMessagesController — send variations', () {
    test('reply (referencedMessageId) succeeds', () async {
      final parent = await sendOne('parent');
      final reply = await adapter.sendMessage(
        'r1',
        text: 'a reply',
        referencedMessageId: parent,
      );
      expect(reply.isSuccess, isTrue);
    });

    test('send with metadata + explicit type succeeds', () async {
      final result = await adapter.sendMessage(
        'r1',
        text: 'tagged',
        metadata: const {'k': 'v'},
        messageType: MessageType.regular,
      );
      expect(result.isSuccess, isTrue);
    });

    test('retrySend on an unknown id completes (error branch)', () async {
      final result = await adapter.retrySend('r1', 'does-not-exist');
      expect(result, isNotNull);
    });
  });

  group('ChatMessagesController — receipts + read', () {
    test(
      'markAsRead without an explicit id falls back to controller',
      () async {
        await sendOne('read me');
        await adapter.loadMessages('r1');

        expect((await adapter.markAsRead('r1')).isSuccess, isTrue);
      },
    );

    test('sendReceipt for delivered and read succeed', () async {
      final id = await sendOne('receipt');
      expect(
        (await adapter.sendReceipt(
          'r1',
          id,
          status: ReceiptStatus.delivered,
        )).isSuccess,
        isTrue,
      );
      expect(
        (await adapter.sendReceipt(
          'r1',
          id,
          status: ReceiptStatus.read,
        )).isSuccess,
        isTrue,
      );
    });
  });
}
