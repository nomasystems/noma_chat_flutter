import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;
  const currentUser = ChatUser(id: 'me', displayName: 'Me');

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    adapter.start();
  });

  group('disconnect resets connection state (resumable)', () {
    test('clears controllers, dm mapping and active room', () async {
      client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
      adapter.dm.registerRoom('bob', 'r1');
      adapter.getChatController('r1');
      adapter.setActiveRoom('r1');

      await adapter.disconnect();

      expect(adapter.findChatController('r1'), isNull);
      expect(adapter.getDmRoomId('bob'), isNull);
      expect(adapter.activeRoomId, isNull);
    });

    test('keeps cross-session caches warm for reconnect', () async {
      adapter.cacheUsers([const ChatUser(id: 'bob', displayName: 'Bob')]);
      adapter.blockedUserIds = {'carol'};

      await adapter.disconnect();

      expect(adapter.findCachedUser('bob'), isNotNull);
      expect(adapter.blockedUserIds, contains('carol'));
    });
  });

  group('signOut wipes every registry', () {
    test('clears user cache, blocked users, presence and voice uploads',
        () async {
      adapter.cacheUsers([const ChatUser(id: 'bob', displayName: 'Bob')]);
      adapter.blockedUserIds = {'carol'};
      client.emitEvent(
        const PresenceChangedEvent(
          userId: 'bob',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.presenceFor('bob'), isNotNull);

      await adapter.signOut();

      expect(adapter.findCachedUser('bob'), isNull);
      expect(adapter.blockedUserIds, isEmpty);
      expect(adapter.presenceFor('bob'), isNull);
      expect(adapter.activeRoomId, isNull);
    });
  });

  group('getChatController auto-propagates the resolved DM peer', () {
    test('seeds otherUsers from the cache without an explicit setOtherUsers',
        () {
      const bob = ChatUser(id: 'bob', displayName: 'Bob');
      adapter.cacheUsers([bob]);
      adapter.dm.registerRoom('bob', 'r1');

      final controller = adapter.getChatController('r1');

      expect(controller.otherUsers, [bob]);
    });

    test('backfills an already-created empty controller on re-open', () {
      final first = adapter.getChatController('r1');
      expect(first.otherUsers, isEmpty);

      const bob = ChatUser(id: 'bob', displayName: 'Bob');
      adapter.cacheUsers([bob]);
      adapter.dm.registerRoom('bob', 'r1');

      final second = adapter.getChatController('r1');
      expect(identical(first, second), isTrue);
      expect(second.otherUsers, [bob]);
    });

    test('never clobbers explicitly supplied otherUsers with cache', () {
      const cached = ChatUser(id: 'bob', displayName: 'Bob');
      const explicit = ChatUser(id: 'bob', displayName: 'Bobby');
      adapter.cacheUsers([cached]);
      adapter.dm.registerRoom('bob', 'r1');

      final controller = adapter.getChatController(
        'r1',
        otherUsers: [explicit],
      );

      expect(controller.otherUsers, [explicit]);
    });

    test('returns no peers for an unresolved room', () {
      final controller = adapter.getChatController('unknown');
      expect(controller.otherUsers, isEmpty);
    });
  });

  group('onDmContactResolved fires when set after first enricher use', () {
    test('late assignment still receives the callback', () async {
      client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
      client.seedRoom(const ChatRoom(id: 'grp', members: ['me', 'x', 'y']));

      await adapter.rooms.load();

      final resolved = <(String, String)>[];
      adapter.onDmContactResolved = (roomId, userId) =>
          resolved.add((roomId, userId));

      client.seedRoom(const ChatRoom(id: 'dm1', members: ['me', 'bob']));
      final materialized = await adapter.dm.ensureMaterialized('bob');
      expect(materialized.isSuccess, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolved, contains((materialized.dataOrThrow, 'bob')));
    });
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });
}
