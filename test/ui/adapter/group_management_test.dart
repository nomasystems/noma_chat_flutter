import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Member management + group info edit smoke tests.
///
/// Confirm the adapter forwards each operation to the corresponding
/// client sub-API and surfaces the ChatResult back to the caller.
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

  test('RoomDefaults.minOtherUsersInGroup is 1', () {
    expect(RoomDefaults.minOtherUsersInGroup, 1);
  });

  test('addMembers returns ChatSuccess for each invite', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'Group'));
    await adapter.rooms.load();

    final result = await adapter.rooms.addMembers('r1', const ['u1', 'u2']);
    expect(result.isSuccess, isTrue);
  });

  test('removeMember returns ChatSuccess when target exists', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'Group', members: ['u1']));
    await adapter.rooms.load();

    final result = await adapter.rooms.removeMember('r1', 'u1');
    expect(result.isSuccess, isTrue);
  });

  test(
    'updateMemberRole returns ChatSuccess when role change is valid',
    () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Group', members: ['u1']));
      await adapter.rooms.load();

      final result = await adapter.rooms.updateMemberRole(
        'r1',
        'u1',
        RoomRole.admin,
      );
      expect(result.isSuccess, isTrue);
    },
  );

  test('updateRoomConfig forwards new name/avatar to client.rooms', () async {
    client.seedRoom(const ChatRoom(id: 'r1', name: 'Old'));
    await adapter.rooms.load();

    final result = await adapter.rooms.updateConfig(
      'r1',
      name: 'New name',
      avatarUrl: 'https://avatar.test/x.png',
    );
    expect(result.isSuccess, isTrue);
  });
}
