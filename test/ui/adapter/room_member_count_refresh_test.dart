import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `RoomListItem.memberCount` is what a room header counts, and it only
/// ever came from a room-detail fetch. A `user_joined` frame added the
/// system card ("… joined") and refreshed the roster, but never went back
/// for the detail — so the header kept the number it had been opened with,
/// contradicting the very card printed underneath it, and kept it across a
/// leave-and-reopen because the cached detail was stale too.
///
/// `user_role_changed` already did the right thing here; join and leave now
/// go through the same door.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() async {
    client = MockChatClient(currentUserId: 'me');
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Big room', members: ['me', 'u1']),
    );
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    await adapter.rooms.load();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('a user_joined frame brings the room header count up to date', () async {
    expect(adapter.roomListController.getRoomById('r1')?.memberCount, isNot(3));

    // The backend's own view of the room after the join.
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Big room', members: ['me', 'u1', 'u2']),
    );
    client.emitEvent(const ChatEvent.userJoined(roomId: 'r1', userId: 'u2'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(adapter.roomListController.getRoomById('r1')?.memberCount, 3);
  });

  test('a user_left frame brings it down again', () async {
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Big room', members: ['me']),
    );
    client.emitEvent(const ChatEvent.userLeft(roomId: 'r1', userId: 'u1'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(adapter.roomListController.getRoomById('r1')?.memberCount, 1);
  });
}
