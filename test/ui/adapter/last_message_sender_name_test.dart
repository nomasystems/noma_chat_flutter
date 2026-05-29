import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `RoomListItem.lastMessageSenderName` enrichment.
///
/// The adapter must populate this field from its `userCache` so the
/// chat list shows the WhatsApp-style "Alice: hola" prefix in groups
/// without the consumer wiring its own resolver.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('A new incoming message updates the room\'s lastMessageSenderName '
      'when the sender is in the user cache', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'Team'));
    await adapter.rooms.load();

    // Seed the user cache with Alice (typical of a room-members fetch).
    adapter.cacheUsers(const [ChatUser(id: 'u1', displayName: 'Alice')]);

    // A new message from Alice arrives.
    client.emitEvent(
      ChatEvent.newMessage(
        message: ChatMessage(
          id: 'm1',
          from: 'u1',
          timestamp: DateTime(2026, 5, 20),
          text: 'hola',
        ),
        roomId: 'r1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final room = adapter.roomListController.getRoomById('r1');
    expect(room?.lastMessageUserId, 'u1');
    expect(room?.lastMessageSenderName, 'Alice');
  });

  test(
    'Messages from the current user never set lastMessageSenderName',
    () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Team'));
      await adapter.rooms.load();

      client.emitEvent(
        ChatEvent.newMessage(
          message: ChatMessage(
            id: 'm1',
            from: 'me',
            timestamp: DateTime(2026, 5, 20),
            text: 'mine',
          ),
          roomId: 'r1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final room = adapter.roomListController.getRoomById('r1');
      expect(room?.lastMessageUserId, 'me');
      expect(room?.lastMessageSenderName, isNull);
    },
  );

  test('Caching the sender later (lazy fetch) refreshes the room prefix '
      'in place', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'Team'));
    await adapter.rooms.load();

    // Message arrives but sender is NOT yet in cache.
    client.emitEvent(
      ChatEvent.newMessage(
        message: ChatMessage(
          id: 'm1',
          from: 'u1',
          timestamp: DateTime(2026, 5, 20),
          text: 'hola',
        ),
        roomId: 'r1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      adapter.roomListController.getRoomById('r1')?.lastMessageSenderName,
      isNull,
    );

    // The user gets cached later (e.g. lazy fetch resolves) →
    // _refreshLastSenderNamesFor stamps the prefix on the room.
    adapter.cacheUsers(const [ChatUser(id: 'u1', displayName: 'Alice')]);
    expect(
      adapter.roomListController.getRoomById('r1')?.lastMessageSenderName,
      'Alice',
    );
  });
}
