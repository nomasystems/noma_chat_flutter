import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The cache phase of `loadMore` serves a page without honouring the cursor
/// and reports no `prevCursor`; taking its word would drop the anchor for
/// older history when the network phase then fails.
void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test(
    'a failed loadMore keeps the older-history cursor it started with',
    () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      client.addMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'older',
        ),
      );
      await adapter.rooms.load();
      await adapter.messages.load('r1');

      final controller = adapter.getChatController('r1');
      controller.setPaginationState(hasMore: true, cursor: 'c1');

      client.messages.throwNextList = true;
      await expectLater(
        () => adapter.messages.loadMore('r1'),
        throwsA(isA<StateError>()),
      );

      expect(controller.oldestMessageCursor, 'c1');
      expect(controller.hasMoreMessages, isTrue);
      expect(controller.isLoadingMore, isFalse);
    },
  );
}
