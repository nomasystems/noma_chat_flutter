import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/_internal/transport/refresh_engine.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// Purges rooms the host tagged as support conversations, keeps every other
/// one read-only — the WB shape this policy was added for.
DeletedRoomPolicy _supportPurges(RoomListItem room) =>
    room.custom?['support'] == true
    ? DeletedRoomPolicy.purge
    : DeletedRoomPolicy.keepReadOnly;

const _me = ChatUser(id: 'u1', displayName: 'Me');

/// A cache whose three kicked-room reads are unreadable while the rest of
/// it still answers — the shape of a corrupted box or a failed disk read,
/// which must never be mistaken for "this room was never cached".
class _UnreadableRoomCache extends MemoryChatLocalDatasource {
  @override
  Future<ChatResult<ChatRoom?>> getRoom(String roomId) async =>
      const ChatFailureResult(StorageFailure('box unreadable'));

  @override
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId) async =>
      const ChatFailureResult(StorageFailure('box unreadable'));

  @override
  Future<ChatResult<List<UnreadRoom>>> getUnreads() async =>
      const ChatFailureResult(StorageFailure('box unreadable'));
}

void main() {
  group('room_deleted over the realtime transport', () {
    late MockChatClient mockClient;
    late MemoryChatLocalDatasource cache;

    setUp(() {
      mockClient = MockChatClient(currentUserId: 'u1');
      cache = MemoryChatLocalDatasource();
    });

    tearDown(() async => mockClient.dispose());

    Future<ChatUiAdapter> buildAdapter({
      DeletedRoomPolicyResolver? policy,
    }) async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: _me,
        cache: cache,
        deletedRoomPolicy: policy,
      );
      addTearDown(adapter.dispose);
      await adapter.connect();
      return adapter;
    }

    /// Seeds a room that exists in the list, in an open controller and in
    /// every cache table a purge is supposed to empty.
    Future<void> seedSupportRoom(ChatUiAdapter adapter) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'support1',
          name: 'Support',
          custom: {'support': true},
        ),
      );
      adapter.getChatController('support1');
      await cache.saveRooms(const [ChatRoom(id: 'support1', name: 'Support')]);
      await cache.saveRoomDetail(
        const RoomDetail(
          id: 'support1',
          type: RoomType.group,
          memberCount: 2,
          userRole: RoomRole.member,
          config: RoomConfig(),
        ),
      );
      await cache.saveMessages('support1', [
        ChatMessage(id: 'm1', from: 'agent', timestamp: DateTime(2026, 9, 1)),
      ]);
      await cache.saveUnreads(const [
        UnreadRoom(roomId: 'support1', unreadMessages: 2),
      ]);
    }

    test('no policy wired keeps the room read-only with its history', () async {
      final adapter = await buildAdapter();
      await seedSupportRoom(adapter);

      mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
      await pumpEventQueue();

      final room = adapter.roomListController.getRoomById('support1');
      expect(room, isNotNull);
      expect(room!.isParticipating, isFalse);
      expect(
        (await cache.getKickedRoomIds()).dataOrThrow,
        contains('support1'),
      );
      expect((await cache.getRoom('support1')).dataOrThrow, isNotNull);
      expect((await cache.getMessages('support1')).dataOrThrow, hasLength(1));
    });

    test(
      'an explicit keepReadOnly policy behaves exactly like no policy',
      () async {
        final adapter = await buildAdapter(
          policy: (_) => DeletedRoomPolicy.keepReadOnly,
        );
        await seedSupportRoom(adapter);

        mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
        await pumpEventQueue();

        final room = adapter.roomListController.getRoomById('support1');
        expect(room!.isParticipating, isFalse);
        expect(
          (await cache.getKickedRoomIds()).dataOrThrow,
          contains('support1'),
        );
        expect((await cache.getRoom('support1')).dataOrThrow, isNotNull);
      },
    );

    test('a purge policy leaves no row and no cached trace', () async {
      final adapter = await buildAdapter(policy: _supportPurges);
      await seedSupportRoom(adapter);

      mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
      await pumpEventQueue();

      expect(adapter.roomListController.getRoomById('support1'), isNull);
      expect((await cache.getRoom('support1')).dataOrThrow, isNull);
      expect((await cache.getRoomDetail('support1')).dataOrThrow, isNull);
      expect((await cache.getMessages('support1')).dataOrThrow, isEmpty);
      expect(
        (await cache.getUnreads()).dataOrThrow.map((u) => u.roomId),
        isNot(contains('support1')),
      );
      // The kicked marker above all: it is what the enricher would rebuild
      // the row from on the next pass.
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
    });

    test('the policy is per room, not per session', () async {
      final adapter = await buildAdapter(policy: _supportPurges);
      await seedSupportRoom(adapter);
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'group1', name: 'Team'),
      );

      mockClient
        ..emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'))
        ..emitEvent(const ChatEvent.roomDeleted(roomId: 'group1'));
      await pumpEventQueue();

      expect(adapter.roomListController.getRoomById('support1'), isNull);
      final group = adapter.roomListController.getRoomById('group1');
      expect(group, isNotNull);
      expect(group!.isParticipating, isFalse);
    });

    test('a throwing policy degrades to keepReadOnly', () async {
      final adapter = await buildAdapter(
        policy: (_) => throw StateError('host bug'),
      );
      await seedSupportRoom(adapter);

      mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
      await pumpEventQueue();

      final room = adapter.roomListController.getRoomById('support1');
      expect(room, isNotNull);
      expect(room!.isParticipating, isFalse);
      expect((await cache.getMessages('support1')).dataOrThrow, hasLength(1));
    });

    test('purging the room the user is inside pops them out of it', () async {
      final adapter = await buildAdapter(policy: _supportPurges);
      await seedSupportRoom(adapter);
      adapter.setActiveRoom('support1');
      final removed = <String>[];
      adapter.onRoomRemoved = (roomId, _, _) => removed.add(roomId);

      mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
      await pumpEventQueue();

      // `onRoomRemoved` is the SDK's public "you are no longer in this
      // room" signal; `NomaChatView` pops itself off it, and a host driving
      // its own navigation reacts to the same callback.
      expect(removed, ['support1']);
      expect(adapter.activeRoomId, isNull);
      expect(adapter.roomListController.getRoomById('support1'), isNull);
      expect(adapter.roomListController.selectedIds, isEmpty);
    });

    test(
      'the event the polling refresh synthesizes purges the same way',
      () async {
        // `RefreshEngine` mints a reason-less `roomDeleted` for any room
        // that dropped out of the listing; it reaches the adapter through
        // the very same event stream, so the policy applies to it too.
        final synthesized = <ChatEvent>[];
        var pass = 0;
        final engine = RefreshEngine(
          getUserRooms: ({String type = 'all'}) async => ChatSuccess(
            pass++ == 0
                ? const UserRooms(
                    rooms: [UnreadRoom(roomId: 'support1', unreadMessages: 0)],
                  )
                : const UserRooms(rooms: []),
          ),
          listMessages: (roomId, {pagination}) async => const ChatSuccess(
            ChatPaginatedResponse(items: [], hasMore: false),
          ),
          emit: synthesized.add,
          config: const PollingConfig(),
        );
        await engine.tick();
        await engine.tick();
        final deleted = synthesized.whereType<RoomDeletedEvent>().single;
        expect(deleted.roomId, 'support1');

        final adapter = await buildAdapter(policy: _supportPurges);
        await seedSupportRoom(adapter);

        mockClient.emitEvent(deleted);
        await pumpEventQueue();

        expect(adapter.roomListController.getRoomById('support1'), isNull);
        expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
      },
    );

    test('a purge tombstones the room, so a listing already in flight '
        'cannot resurrect it', () async {
      final adapter = await buildAdapter(policy: _supportPurges);
      await seedSupportRoom(adapter);

      mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
      await pumpEventQueue();

      // The `getUserRooms` request that was already on the wire when the
      // room was deleted lands now, still carrying the room. Without the
      // tombstone it would come back fully writable and stay: the kicked
      // marker is gone and no second `room_deleted` is coming.
      adapter.roomListController.mergeRooms(const [
        RoomListItem(id: 'support1', name: 'Support'),
      ], authoritative: true);

      expect(
        adapter.roomListController.rooms.map((r) => r.id),
        isNot(contains('support1')),
      );
      expect(
        (await cache.getDeletedRoomIds()).dataOrThrow,
        contains('support1'),
      );
    });

    test(
      'the user-driven delete of a kicked chat leaves no tombstone, as before',
      () async {
        // `ChatRoomOption.deleteKickedChat` shares the purge helper but must
        // stay the operation it always was — a plain removal, so a peer
        // writing again can still bring the conversation back.
        final adapter = await buildAdapter();
        await seedSupportRoom(adapter);

        await adapter.rooms.deleteKicked('support1');
        await pumpEventQueue();

        expect(adapter.roomListController.getRoomById('support1'), isNull);
        expect((await cache.getDeletedRoomIds()).dataOrThrow, isEmpty);
      },
    );
  });

  group('membership revoked without a room_deleted', () {
    late MockChatClient mockClient;
    late MemoryChatLocalDatasource cache;

    setUp(() {
      mockClient = MockChatClient(currentUserId: 'u1');
      cache = MemoryChatLocalDatasource();
    });

    tearDown(() async => mockClient.dispose());

    Future<ChatUiAdapter> buildAdapter({
      DeletedRoomPolicyResolver? policy,
    }) async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: _me,
        cache: cache,
        deletedRoomPolicy: policy,
      );
      addTearDown(adapter.dispose);
      await adapter.connect();
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'support1',
          name: 'Support',
          custom: {'support': true},
        ),
      );
      adapter.getChatController('support1');
      await cache.saveRooms(const [ChatRoom(id: 'support1', name: 'Support')]);
      return adapter;
    }

    test('an operator kick ends a purge-policy room right away', () async {
      // The operator removes the user instead of deleting the room. Under
      // `keepReadOnly` that leaves a browsable read-only row; under `purge`
      // the conversation is over, and the host hears about it now rather
      // than whenever the next room-list pass happens to run.
      final adapter = await buildAdapter(policy: _supportPurges);
      final removed = <String>[];
      adapter.onRoomRemoved = (roomId, _, _) => removed.add(roomId);

      mockClient.emitEvent(
        const ChatEvent.userLeft(
          roomId: 'support1',
          userId: 'u1',
          actorUserId: 'operator',
        ),
      );
      await pumpEventQueue();

      expect(adapter.roomListController.getRoomById('support1'), isNull);
      expect(removed, ['support1']);
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
      expect((await cache.getRoom('support1')).dataOrThrow, isNull);
      expect(
        (await cache.getDeletedRoomIds()).dataOrThrow,
        contains('support1'),
      );
    });

    test('an operator kick still keeps a default room read-only', () async {
      final adapter = await buildAdapter();
      final removed = <String>[];
      adapter.onRoomRemoved = (roomId, _, _) => removed.add(roomId);

      mockClient.emitEvent(
        const ChatEvent.userLeft(
          roomId: 'support1',
          userId: 'u1',
          actorUserId: 'operator',
        ),
      );
      await pumpEventQueue();

      final room = adapter.roomListController.getRoomById('support1');
      expect(room, isNotNull);
      expect(room!.isParticipating, isFalse);
      expect(removed, isEmpty);
      expect(
        (await cache.getKickedRoomIds()).dataOrThrow,
        contains('support1'),
      );
    });

    test('leaving a purge-policy room ends it too', () async {
      final adapter = await buildAdapter(policy: _supportPurges);
      final removed = <String>[];
      adapter.onRoomRemoved = (roomId, _, _) => removed.add(roomId);

      final result = await adapter.rooms.leave('support1');
      await pumpEventQueue();

      expect(result.isSuccess, isTrue);
      expect(adapter.roomListController.getRoomById('support1'), isNull);
      expect(removed, ['support1']);
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
    });

    test(
      'leaving a default room keeps it browsable, as it always did',
      () async {
        final adapter = await buildAdapter();

        final result = await adapter.rooms.leave('support1');
        await pumpEventQueue();

        expect(result.isSuccess, isTrue);
        final room = adapter.roomListController.getRoomById('support1');
        expect(room, isNotNull);
        expect(room!.isParticipating, isFalse);
        expect(
          (await cache.getKickedRoomIds()).dataOrThrow,
          contains('support1'),
        );
      },
    );
  });

  group('cold start: the kicked marker replayed from cache', () {
    late MockChatClient mock;
    late RoomListController roomList;
    late MemoryChatLocalDatasource cache;
    late DmContactRegistry dmContacts;

    setUp(() async {
      mock = MockChatClient(currentUserId: 'u1');
      roomList = RoomListController();
      dmContacts = DmContactRegistry();
      cache = MemoryChatLocalDatasource();
      // What a device that was kicked out of a support room before the
      // last shutdown holds on disk.
      await cache.markKicked('support1');
      await cache.saveRooms(const [
        ChatRoom(id: 'support1', name: 'Support', custom: {'support': true}),
      ]);
      await cache.saveMessages('support1', [
        ChatMessage(id: 'm1', from: 'agent', timestamp: DateTime(2026, 9, 1)),
      ]);
      await cache.saveUnreads(const [
        UnreadRoom(roomId: 'support1', unreadMessages: 0),
      ]);
      mock.seedRoom(const ChatRoom(id: 'live1', name: 'Live room'));
    });

    tearDown(() async {
      roomList.dispose();
      await mock.dispose();
    });

    RoomEnricher buildEnricher({
      DeletedRoomPolicyResolver? policy,
      List<String>? removedControllers,
      List<String>? roomsRemoved,
      ChatLocalDatasource? cacheOverride,
    }) {
      final enricher = RoomEnricher(
        client: mock,
        controllers: ChatControllerRegistry(),
        roomList: roomList,
        dmContacts: dmContacts,
        userCache: UserCacheService(api: mock.users, isDisposed: () => false),
        blockedUsers: BlockedUsersRegistry(),
        presence: PresenceRegistry(
          api: mock.presence,
          roomList: roomList,
          dmContacts: dmContacts,
          isDisposed: () => false,
        ),
        currentUser: () => _me,
        cache: cacheOverride ?? cache,
        l10n: () => ChatUiLocalizations.en,
        initializedNotifier: ValueNotifier<bool>(false),
        connectionStateNotifier: ValueNotifier<ChatConnectionState>(
          ChatConnectionState.disconnected,
        ),
        isDisposed: () => false,
        isDmDetail: (detail) => detail.type == RoomType.oneToOne,
        findCachedUser: (_) => null,
        cacheUsers: (_) {},
        ensureUserCached: (_) async {},
        updateRoomLastMessage: (_, _) {},
        removeChatController: (id) => removedControllers?.add(id),
        deletedRoomPolicy: policy,
        onRoomRemoved: () => roomsRemoved == null
            ? null
            : (roomId, _, _) => roomsRemoved.add(roomId),
      );
      addTearDown(enricher.dispose);
      return enricher;
    }

    test('keepReadOnly rebuilds the read-only row, as it always did', () async {
      final enricher = buildEnricher();

      await enricher.loadAll();
      await pumpEventQueue();

      final kicked = roomList.allRooms.where((r) => r.id == 'support1').single;
      expect(kicked.isParticipating, isFalse);
      expect(kicked.custom, {'support': true});
      expect(
        (await cache.getKickedRoomIds()).dataOrThrow,
        contains('support1'),
      );
    });

    test('purge drops the row the cache could still rebuild', () async {
      final removed = <String>[];
      final enricher = buildEnricher(
        policy: _supportPurges,
        removedControllers: removed,
      );

      await enricher.loadAll();
      await pumpEventQueue();

      expect(roomList.allRooms.map((r) => r.id), isNot(contains('support1')));
      expect(removed, contains('support1'));
      // Marker gone, so no later pass can bring the room back.
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
      expect((await cache.getRoom('support1')).dataOrThrow, isNull);
      expect((await cache.getMessages('support1')).dataOrThrow, isEmpty);
    });

    test('a purged room stays gone across a second load', () async {
      final enricher = buildEnricher(policy: _supportPurges);

      await enricher.loadAll();
      await pumpEventQueue();
      await enricher.loadAll();
      await pumpEventQueue();

      expect(roomList.allRooms.map((r) => r.id), isNot(contains('support1')));
      expect(roomList.allRooms.map((r) => r.id), contains('live1'));
    });

    test('the purge reports itself, so a view open on the room pops', () async {
      // The reachable shape: the user was kicked out of the support room
      // while sitting inside it (the kick keeps the controller alive by
      // design), and it is this pass — not the event — that purges. A
      // controller disposed under a mounted `NomaChatView` with no
      // `onRoomRemoved` would leave the user staring at a dead screen.
      final removedRooms = <String>[];
      final removedControllers = <String>[];
      final enricher = buildEnricher(
        policy: _supportPurges,
        removedControllers: removedControllers,
        roomsRemoved: removedRooms,
      );

      await enricher.loadAll();
      await pumpEventQueue();

      expect(removedRooms, ['support1']);
      expect(removedControllers, contains('support1'));
      expect(roomList.allRooms.map((r) => r.id), isNot(contains('support1')));
    });

    test('a stale cache listing that still names the purged room paints '
        'no row', () async {
      // Non-authoritative pass: the room is still in the cached listing, so
      // the marker's id is among the ids this pass carries and the
      // hydration branch is never reached. The row has to be dropped from
      // the batch before it is painted.
      mock.seedRoom(
        const ChatRoom(
          id: 'support1',
          name: 'Support',
          custom: {'support': true},
        ),
      );
      final enricher = buildEnricher(policy: _supportPurges);

      await enricher.hydrateFromCache();
      await pumpEventQueue();

      expect(roomList.allRooms.map((r) => r.id), isNot(contains('support1')));
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
      expect((await cache.getRoom('support1')).dataOrThrow, isNull);
    });

    test('a kicked marker with nothing cached behind it is dropped, not '
        'painted', () async {
      // The half-state a failed `unmarkKicked` (or an eviction that took
      // the rows but not the never-evictable marker) leaves behind. There
      // is no `custom` to decide on, so no policy can recognise the room:
      // painting the stub would strand an unnamed, empty, read-only row
      // that nothing can ever remove.
      await cache.clear();
      await cache.markKicked('ghost1');
      final enricher = buildEnricher(policy: _supportPurges);

      await enricher.loadAll();
      await pumpEventQueue();

      expect(roomList.allRooms.map((r) => r.id), isNot(contains('ghost1')));
      expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
    });

    test('an unreadable cache is not taken for an empty one — the marker '
        'outlives the pass', () async {
      // Dropping a durable marker is destructive and irreversible, so it
      // may only follow a read that actually answered. A failed one leaves
      // the historical degraded stub in place instead.
      final broken = _UnreadableRoomCache();
      await broken.markKicked('support1');
      final enricher = buildEnricher(cacheOverride: broken);

      await enricher.loadAll();
      await pumpEventQueue();

      expect(roomList.allRooms.map((r) => r.id), contains('support1'));
      expect(
        (await broken.getKickedRoomIds()).dataOrThrow,
        contains('support1'),
      );
    });
  });
}
