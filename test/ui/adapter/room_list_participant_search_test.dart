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

  test('a group is found by a member who never wrote in it', () {
    list().addRoom(
      const RoomListItem(
        id: 'g6',
        name: 'Weekend trip',
        isGroup: true,
        lastMessage: 'on my way',
        lastMessageUserId: 'u2',
      ),
    );
    adapter.cacheUsers([
      const ChatUser(id: 'u2', displayName: 'Alice Johnson'),
      const ChatUser(id: 'u7', displayName: 'Dana Silent'),
    ]);
    adapter.recordRoomRoster('g6', ['me', 'u2', 'u7']);

    list().setFilter('silent');

    expect(list().rooms.map((r) => r.id), ['g6']);
    expect(list().matchedParticipantFor('g6'), 'Dana Silent');
  });

  test('a roster that lands after the filter re-opens it', () {
    list().addRoom(
      const RoomListItem(id: 'g7', name: 'Weekend trip', isGroup: true),
    );
    adapter.cacheUsers([const ChatUser(id: 'u8', displayName: 'Erin')]);

    list().setFilter('erin');
    expect(list().rooms, isEmpty);

    adapter.recordRoomRoster('g7', ['u8']);

    expect(list().rooms.map((r) => r.id), ['g7']);
    expect(list().matchedParticipantFor('g7'), 'Erin');
  });

  test('the local user stays out of the roster match', () {
    list().addRoom(
      const RoomListItem(id: 'g8', name: 'Weekend trip', isGroup: true),
    );
    adapter.recordRoomRoster('g8', ['me']);

    list().setFilter('me');

    expect(list().rooms, isEmpty);
  });

  test('a roster page adds to what is already known', () {
    list().addRoom(
      const RoomListItem(id: 'g9', name: 'Weekend trip', isGroup: true),
    );
    adapter.cacheUsers([
      const ChatUser(id: 'u9', displayName: 'Frank'),
      const ChatUser(id: 'u10', displayName: 'Gina'),
    ]);
    adapter.recordRoomRoster('g9', ['u9'], complete: false);
    adapter.recordRoomRoster('g9', ['u10'], complete: false);

    expect(adapter.roomRosterOf('g9'), {'u9', 'u10'});

    list().setFilter('frank');
    expect(list().rooms.map((r) => r.id), ['g9']);

    list().setFilter('gina');
    expect(list().rooms.map((r) => r.id), ['g9']);
  });

  test('a complete roster replaces the one before it', () {
    list().addRoom(
      const RoomListItem(id: 'g10', name: 'Weekend trip', isGroup: true),
    );
    adapter.cacheUsers([
      const ChatUser(id: 'u11', displayName: 'Hank'),
      const ChatUser(id: 'u12', displayName: 'Iris'),
    ]);
    adapter.recordRoomRoster('g10', ['u11']);
    adapter.recordRoomRoster('g10', ['u12']);

    expect(adapter.roomRosterOf('g10'), {'u12'});

    list().setFilter('hank');
    expect(list().rooms, isEmpty);
  });

  test('a member who joins becomes searchable, one who leaves stops', () async {
    list().addRoom(
      const RoomListItem(id: 'g11', name: 'Weekend trip', isGroup: true),
    );
    adapter.cacheUsers([const ChatUser(id: 'u13', displayName: 'Jane')]);
    adapter.start();

    client.emitEvent(const UserJoinedEvent(roomId: 'g11', userId: 'u13'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    list().setFilter('jane');
    expect(list().rooms.map((r) => r.id), ['g11']);

    client.emitEvent(const UserLeftEvent(roomId: 'g11', userId: 'u13'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    list().setFilter('');
    list().setFilter('jane');
    expect(list().rooms, isEmpty);
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
