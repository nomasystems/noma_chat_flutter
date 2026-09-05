import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// [ChatUiAdapter] wires the room list's participant filter to the names it
/// can already resolve, so searching a person's name finds the conversation
/// they are in even when the row is titled something else entirely.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  RoomListController list() => adapter.roomListController;

  test('the adapter installs a resolver on its own room list', () {
    expect(list().participantNameResolver, isNotNull);
  });

  test('a group is found by the name of whoever wrote last', () {
    list().addRoom(
      const RoomListItem(
        id: 'g1',
        name: 'Weekend trip',
        isGroup: true,
        lastMessage: 'on my way',
        lastMessageUserId: 'u2',
      ),
    );
    adapter.cacheUsers([
      const ChatUser(id: 'u2', displayName: 'Alice Johnson'),
    ]);

    list().setFilter('johnson');

    expect(list().rooms.map((r) => r.id), ['g1']);
    expect(list().matchedParticipantFor('g1'), 'Alice Johnson');
  });

  test('an unnamed one-to-one row is found by its peer', () {
    list().addRoom(const RoomListItem(id: 'dm1', otherUserId: 'u3'));
    adapter.cacheUsers([const ChatUser(id: 'u3', displayName: 'Bob Smith')]);

    list().setFilter('smith');

    expect(list().rooms.map((r) => r.id), ['dm1']);
  });

  test('an id nobody can name never matches on its own id', () {
    list().addRoom(
      const RoomListItem(
        id: 'g2',
        name: 'Other',
        isGroup: true,
        lastMessageUserId: 'deadbeef-0000',
      ),
    );

    list().setFilter('deadbeef');

    expect(list().rooms, isEmpty);
  });

  test('the local user is not a searchable participant', () {
    list().addRoom(
      const RoomListItem(
        id: 'g3',
        name: 'Weekend trip',
        isGroup: true,
        lastMessageUserId: 'me',
      ),
    );

    list().setFilter('me');

    expect(list().rooms, isEmpty);
  });

  test('a name that lands later re-opens the filter', () {
    list().addRoom(
      const RoomListItem(
        id: 'g4',
        name: 'Weekend trip',
        isGroup: true,
        lastMessageUserId: 'u4',
      ),
    );
    list().setFilter('carol');
    expect(list().rooms, isEmpty);

    adapter.cacheUsers([const ChatUser(id: 'u4', displayName: 'Carol')]);

    expect(list().rooms.map((r) => r.id), ['g4']);
  });

  test('a host resolver replaces the built-in one', () {
    list().addRoom(
      const RoomListItem(id: 'g5', name: 'Weekend trip', isGroup: true),
    );
    list().setParticipantNameResolver((room) => const ['Dana']);

    list().setFilter('dana');

    expect(list().rooms.map((r) => r.id), ['g5']);
    expect(list().matchedParticipantFor('g5'), 'Dana');
  });
}
