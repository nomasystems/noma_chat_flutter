import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `RoomTitleResolver`. The adapter exposes a hook so apps
/// can override the title computation per room; the default reproduces
/// WhatsApp's behaviour (DMs render the peer's display name, groups
/// render the server-provided `name`).
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test(
    'Default resolver: groups surface the server-provided room name',
    () async {
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
      client.seedRoom(
        const ChatRoom(id: 'g1', name: 'Team Chat', members: ['u1', 'u2']),
      );
      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        adapter.roomListController.getRoomById('g1')?.displayName,
        'Team Chat',
      );
    },
  );

  test('Custom resolver wins over the default and receives the right '
      'RoomTitleContext', () async {
    RoomTitleContext? lastContext;
    adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      roomTitleResolver: (ctx) {
        lastContext = ctx;
        return '★ ${ctx.currentItem.name ?? "?"}';
      },
    );
    adapter.start();
    client.seedUser(alice);
    client.seedRoom(const ChatRoom(id: 'g1', name: 'Foo', members: ['u1']));
    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(adapter.roomListController.getRoomById('g1')?.displayName, '★ Foo');
    expect(lastContext, isNotNull);
    expect(lastContext!.currentUser.id, 'me');
  });

  test('Custom resolver returning null falls back to the room name '
      '(the default chain)', () async {
    adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      roomTitleResolver: (_) => null,
    );
    adapter.start();
    client.seedRoom(const ChatRoom(id: 'g1', name: 'Plain', members: ['u1']));
    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(adapter.roomListController.getRoomById('g1')?.displayName, 'Plain');
  });
}
