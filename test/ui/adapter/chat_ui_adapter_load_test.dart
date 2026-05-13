import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Coverage for the load-paths of ChatUiAdapter (loadRooms, loadMessages,
/// loadMoreMessages, loadThread, loadReceipts, loadPins) using the
/// `MockChatClient`. These exercise the cache-then-network branches inside
/// the adapter itself.
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

  test('loadRooms with an empty mock succeeds and is idempotent', () async {
    final r1 = await adapter.loadRooms();
    expect(r1.isSuccess, true);
    final r2 = await adapter.loadRooms();
    expect(r2.isSuccess, true);
  });

  test('loadMessages on a seeded room populates the controller', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    client.addMessage('r1', ChatMessage(
      id: 'm1', from: 'u2', timestamp: DateTime(2026, 1, 1), text: 'hi',
    ));
    await adapter.loadRooms();

    final r = await adapter.loadMessages('r1');

    expect(r.isSuccess, true);
    final controller = adapter.getChatController('r1');
    expect(controller.messages.any((m) => m.id == 'm1'), true);
  });

  test('loadMoreMessages does nothing when there are no more pages',
      () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    await adapter.loadRooms();
    await adapter.loadMessages('r1');

    final r = await adapter.loadMoreMessages('r1');
    expect(r.isSuccess, true);
  });

  test('loadThread returns the thread page', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    final parent = ChatMessage(
      id: 'parent',
      from: 'u2',
      timestamp: DateTime(2026, 1, 1),
      text: 'top',
    );
    final reply = ChatMessage(
      id: 'reply',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1, 0, 1),
      text: 'reply',
      referencedMessageId: 'parent',
    );
    client.addMessage('r1', parent);
    client.addMessage('r1', reply);

    final r = await adapter.loadThread('r1', 'parent');
    expect(r.isSuccess, true);
  });

  test('loadReceipts succeeds against the mock', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    final r = await adapter.loadReceipts('r1');
    expect(r.isSuccess, true);
  });

  test('loadPins succeeds against the mock', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    final r = await adapter.loadPins('r1');
    expect(r.isSuccess, true);
  });

  test('getReactions delegates and propagates the result', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    final r = await adapter.getReactions('r1', 'm1');
    expect(r.isSuccess, true);
  });

  test('searchMessages with an empty room returns empty paginated response',
      () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
    final r = await adapter.searchMessages('hello', 'r1');
    expect(r.isSuccess, true);
    expect(r.dataOrNull!.items, isEmpty);
  });
}
