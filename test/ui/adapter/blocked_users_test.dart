import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// block/unblock + privacy.
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

  test('Setting blockedUserIds fires onBlockedUsersChanged once', () async {
    Set<String>? lastSnapshot;
    adapter.onBlockedUsersChanged = (s) => lastSnapshot = s;
    adapter.blockedUserIds = {'u1', 'u2'};
    expect(lastSnapshot, {'u1', 'u2'});
    expect(adapter.blockedUserIds, {'u1', 'u2'});
  });

  test(
    'Setting blockedUserIds keeps DM rooms with blocked others (read-only, WhatsApp parity)',
    () async {
      // Decision A: blocking a contact KEEPS their DM chat in the list and
      // renders the read-only blocked composer (BlockedChatBanner) instead of
      // pruning the row. The conversation must not vanish from either peer's
      // list. The enricher resolves DMs lazily; for this unit test we inject
      // the RoomListItem directly.
      adapter.roomListController.setRooms([
        const RoomListItem(id: 'dm-with-u1', otherUserId: 'u1'),
        const RoomListItem(id: 'dm-with-u3', otherUserId: 'u3'),
      ]);
      adapter.blockedUserIds = {'u1'};
      expect(adapter.roomListController.allRooms.map((r) => r.id), [
        'dm-with-u1',
        'dm-with-u3',
      ]);
    },
  );

  test('blockedUserIds is wrapped as an unmodifiable view', () {
    adapter.blockedUserIds = {'u1'};
    expect(
      () => adapter.blockedUserIds.add('u2'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
