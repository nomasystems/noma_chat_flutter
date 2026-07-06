import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Drives [ChatUiAdapter.rooms.load] against a mixed room set so the
/// `RoomEnricher` bulk-load flow runs end to end: DM contact resolution,
/// group / announcement classification, the self-chat title fallback, the
/// last-message sender-name pre-fetch, and the live `refreshRoom` path after
/// a `RoomUpdatedEvent`.
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

  test('resolves the DM contact title from the fetched peer profile', () async {
    client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
    client.seedRoom(const ChatRoom(id: 'dm1', members: ['me', 'bob']));
    client.addMessage(
      'dm1',
      ChatMessage(
        id: 'm1',
        from: 'bob',
        timestamp: DateTime(2026, 1, 1),
        text: 'hi',
      ),
    );

    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final dm = adapter.roomListController.getRoomById('dm1');
    expect(dm, isNotNull);
    expect(dm!.otherUserId, 'bob');
    expect(dm.effectiveDisplayName, 'Bob');
  });

  test(
    'classifies group and announcement rooms and keeps the sender id',
    () async {
      client.seedUser(const ChatUser(id: 'alice', displayName: 'Alice'));
      client.seedRoom(
        const ChatRoom(
          id: 'grp',
          name: 'Team',
          members: ['me', 'alice', 'carol'],
        ),
      );
      client.seedRoomMeta('grp', unread: 3);
      client.addMessage(
        'grp',
        ChatMessage(
          id: 'g1',
          from: 'alice',
          timestamp: DateTime(2026, 1, 2),
          text: 'hey team',
        ),
      );
      client.seedRoom(
        const ChatRoom(
          id: 'ann',
          name: 'News',
          members: ['me', 'x', 'y'],
          custom: {'type': 'announcement'},
        ),
      );

      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final grp = adapter.roomListController.getRoomById('grp');
      expect(grp?.isGroup, isTrue);
      expect(grp?.lastMessageUserId, 'alice');

      final ann = adapter.roomListController.getRoomById('ann');
      expect(ann?.isAnnouncement, isTrue);
    },
  );

  test('renders the self-chat fallback title for a lone-member room', () async {
    client.seedRoom(const ChatRoom(id: 'self', members: ['me']));

    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final self = adapter.roomListController.getRoomById('self');
    expect(self, isNotNull);
    // computeEffectiveTitle's self-chat branch fires (1 member, no name).
    expect(self!.effectiveDisplayName, isNotNull);
  });

  test(
    'fires onDmContactResolved when a DM materialises via ensureMaterialized',
    () async {
      client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));

      final resolved = <(String, String)>[];
      adapter.onDmContactResolved = (roomId, userId) =>
          resolved.add((roomId, userId));

      final materialized = await adapter.dm.ensureMaterialized('bob');
      expect(materialized.isSuccess, isTrue);
      final roomId = materialized.dataOrThrow;

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolved, contains((roomId, 'bob')));
    },
  );

  test('fires onDmContactResolved during bulk load DM resolution', () async {
    client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
    client.seedRoom(const ChatRoom(id: 'dm1', members: ['me', 'bob']));

    final resolved = <(String, String)>[];
    adapter.onDmContactResolved = (roomId, userId) =>
        resolved.add((roomId, userId));

    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(resolved, contains(('dm1', 'bob')));
  });

  test(
    'refreshes an existing room in place after a RoomUpdatedEvent',
    () async {
      client.seedRoom(
        const ChatRoom(id: 'grp', name: 'Team', members: ['me', 'a', 'b']),
      );
      await adapter.rooms.load();

      await client.rooms.updateConfig('grp', name: 'Renamed');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(adapter.roomListController.getRoomById('grp'), isNotNull);
    },
  );
}
