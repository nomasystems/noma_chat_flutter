import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Duplicate DM rooms across the same pair collapse to one row
/// after `loadRooms` resolves. The room with history wins; the empty one
/// is removed from the list (and the local cache).
///
/// The harness scenario reproducing this bug: a race between
/// `findExistingDmRoom` returning null (DM resolution not yet finished)
/// and a tap on a contact in the suggestion bar that calls
/// `ensureDmRoomMaterialized`, ending up with two server-side DMs for
/// the same pair. The user then sees both rows after a hot restart.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      // MockRoomsApi.get always returns RoomType.group. Drive the DM
      // detection by member count instead so the dedupe path runs.
      isDmRoom: (detail) => detail.memberCount == 2,
    );
    adapter.start();
    client.seedUser(alice);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test(
    'two DM rooms with the same contact collapse to the one with history',
    () async {
      // First DM: has a message (history).
      client.seedRoom(
        const ChatRoom(
          id: 'room-old',
          owner: 'me',
          members: ['me', 'u1'],
          audience: RoomAudience.unrestricted,
          allowInvitations: false,
        ),
      );
      client.addMessage(
        'room-old',
        ChatMessage(
          id: 'msg-1',
          from: 'u1',
          timestamp: DateTime.utc(2026, 5, 19, 10),
          text: 'hello',
        ),
      );

      // Second DM: same other user, no messages — typical race ghost.
      client.seedRoom(
        const ChatRoom(
          id: 'room-new-empty',
          owner: 'me',
          members: ['me', 'u1'],
          audience: RoomAudience.unrestricted,
          allowInvitations: false,
        ),
      );

      // Pre-populate `lastMessageTime` on the older one so the dedupe
      // heuristic can decide. `MockRoomsApi.getUserRooms` returns empty
      // unread/lastMessage info, so the adapter sets it via room list
      // updates — we simulate that by directly seeding the list with
      // `updateRoom` after `loadRooms`. In the real harness the same
      // info comes from the server's `lastUnreadMessage`.
      final loadResult = await adapter.rooms.load();
      expect(loadResult.isSuccess, isTrue);

      // Inject lastMessageTime on the room with history so the dedupe
      // heuristic picks it. Production servers provide this via
      // `getUserRooms` + `lastUnreadMessage`.
      final old = adapter.roomListController.getRoomById('room-old')!;
      adapter.roomListController.updateRoom(
        old.copyWith(
          lastMessageTime: DateTime.utc(2026, 5, 19, 10),
          lastMessage: 'hello',
          lastMessageUserId: 'u1',
        ),
      );

      // Re-trigger DM resolution by re-loading. This simulates a hot
      // restart that re-runs DM enrichment and applies dedupe.
      await adapter.rooms.load();

      // Only one DM row remains.
      final dmRooms = adapter.roomListController.allRooms
          .where((r) => r.otherUserId == 'u1')
          .toList();
      expect(dmRooms.length, 1, reason: 'duplicate DM should be collapsed');
      expect(
        dmRooms.single.id,
        'room-old',
        reason: 'the room with history wins',
      );

      // The empty room is no longer in the list.
      expect(adapter.roomListController.getRoomById('room-new-empty'), isNull);

      // The dm-by-contact cache points at the surviving room.
      expect(adapter.dm.getRoomId('u1'), 'room-old');
    },
  );

  test('a single DM stays untouched (no false-positive dedupe)', () async {
    client.seedRoom(
      const ChatRoom(
        id: 'room-only',
        owner: 'me',
        members: ['me', 'u1'],
        audience: RoomAudience.unrestricted,
        allowInvitations: false,
      ),
    );
    await adapter.rooms.load();
    final dms = adapter.roomListController.allRooms
        .where((r) => r.otherUserId == 'u1')
        .toList();
    expect(dms.length, 1);
    expect(dms.single.id, 'room-only');
  });
}
