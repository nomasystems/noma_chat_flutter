import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// A transport that is not there. Every method throws and every call is
/// counted, so "the cache pass emitted nothing" is an observation about
/// the wire rather than about timing.
class _OfflineRest extends Mock implements RestClient {
  int calls = 0;

  /// Parks the NEXT request until completed, then fails it like the rest.
  /// Lets a test put a session boundary inside a network round-trip
  /// without ever letting one succeed.
  Completer<void>? gate;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    final parked = gate;
    gate = null;
    if (parked != null) {
      return parked.future.then<Never>((_) => throw Exception('offline'));
    }
    throw Exception('offline');
  }
}

/// A store whose roster read can be parked, so a test can drop a session
/// boundary in the middle of a DM resolution instead of racing it.
class _GatedStore extends MemoryChatLocalDatasource {
  Completer<void>? rosterGate;
  Completer<void>? userGate;

  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>?>> getRoomMembers(
    String roomId,
  ) async {
    final gate = rosterGate;
    rosterGate = null;
    if (gate != null) await gate.future;
    return super.getRoomMembers(roomId);
  }

  @override
  Future<ChatResult<ChatUser?>> getUser(String userId) async {
    final gate = userGate;
    userGate = null;
    if (gate != null) await gate.future;
    return super.getUser(userId);
  }
}

class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  ChatResult<UserRooms> cacheResult = const ChatFailureResult(
    NetworkFailure('No cached data available'),
  );
  ChatResult<UserRooms> networkResult = const ChatFailureResult(
    NetworkFailure('offline'),
  );

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async =>
      cachePolicy == CachePolicy.cacheOnly ? cacheResult : networkResult;

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) => _delegate.get(roomId, cachePolicy: cachePolicy);

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Rooms come from a script; members and users come from the REAL cached
/// APIs wired to a real store and a dead transport — the chain this item
/// exists to build.
class _ScriptedClient implements ChatClient {
  _ScriptedClient(this._delegate, this.members, this.users)
    : rooms = _ScriptedRoomsApi(_delegate.rooms);

  final MockChatClient _delegate;

  @override
  final _ScriptedRoomsApi rooms;
  @override
  final MembersApi members;
  @override
  final UsersApi users;

  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  MockPresenceApi get presence => _delegate.presence;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const bob = ChatUser(
    id: 'bob',
    displayName: 'Bob',
    avatarUrl: 'https://cdn/bob.png',
  );

  late MockChatClient mock;
  late _ScriptedClient client;
  late _OfflineRest rest;
  late _GatedStore store;
  late RoomListController roomList;
  late RoomEnricher enricher;
  late Map<String, ChatUser> knownUsers;
  late DmContactRegistry dmContacts;
  late List<String> ensureUserCalls;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    rest = _OfflineRest();
    store = _GatedStore();
    final cm = CacheManager(config: const CacheConfig());
    client = _ScriptedClient(
      mock,
      MembersApi(rest: rest, userId: 'me', cache: store, cacheManager: cm),
      UsersApi(rest: rest, cache: store, cacheManager: cm),
    );
    roomList = RoomListController();
    knownUsers = {};
    ensureUserCalls = [];
    dmContacts = DmContactRegistry();
    enricher = RoomEnricher(
      client: client,
      controllers: ChatControllerRegistry(),
      roomList: roomList,
      dmContacts: dmContacts,
      userCache: UserCacheService(api: client.users, isDisposed: () => false),
      blockedUsers: BlockedUsersRegistry(),
      presence: PresenceRegistry(
        api: client.presence,
        roomList: roomList,
        dmContacts: dmContacts,
        isDisposed: () => false,
      ),
      currentUser: () => me,
      cache: null,
      l10n: () => ChatUiLocalizations.en,
      initializedNotifier: ValueNotifier<bool>(false),
      connectionStateNotifier: ValueNotifier<ChatConnectionState>(
        ChatConnectionState.disconnected,
      ),
      isDisposed: () => false,
      isDmDetail: (detail) => detail.type == RoomType.oneToOne,
      findCachedUser: (id) => knownUsers[id],
      cacheUsers: (users) {
        for (final u in users) {
          knownUsers[u.id] = u;
        }
      },
      ensureUserCached: (id) async => ensureUserCalls.add(id),
      updateRoomLastMessage: (_, _) {},
      removeChatController: (_) {},
    );
  });

  tearDown(() async {
    enricher.dispose();
    roomList.dispose();
    await mock.dispose();
  });

  /// A DM with Bob, exactly as a cold start finds it: the room list is on
  /// disk, `DmContactRegistry` is empty and nothing is in memory.
  UserRooms seedDm() {
    mock.seedRoom(const ChatRoom(id: 'dm1', members: ['me', 'bob']));
    return UserRooms(
      rooms: [
        UnreadRoom(
          roomId: 'dm1',
          unreadMessages: 1,
          lastMessage: 'hola',
          lastMessageId: 'm1',
          lastMessageUserId: 'bob',
          lastMessageTime: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
  }

  test('a cold start names the DM row from disk alone — roster and peer '
      'profile both come out of the store, before any network pass', () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());
    await store.saveRoomMembers(
      'dm1',
      const ChatPaginatedResponse(
        items: [RoomUser(userId: 'me'), RoomUser(userId: 'bob')],
        hasMore: false,
        totalCount: 2,
      ),
    );
    await store.saveUsers([bob]);

    await enricher.loadAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final row = roomList.getRoomById('dm1')!;
    expect(row.otherUserId, 'bob');
    expect(row.displayName, 'Bob');
    expect(row.avatarUrl, 'https://cdn/bob.png');
  });

  test('and it emits nothing: the whole resolution stayed on disk', () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());
    await store.saveRoomMembers(
      'dm1',
      const ChatPaginatedResponse(
        items: [RoomUser(userId: 'me'), RoomUser(userId: 'bob')],
        hasMore: false,
        totalCount: 2,
      ),
    );
    await store.saveUsers([bob]);

    await enricher.loadAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(rest.calls, 0);
  });

  test('with no roster stored the row stays as it was and still nothing '
      'goes to the wire', () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());

    await enricher.loadAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final row = roomList.getRoomById('dm1')!;
    expect(row.otherUserId, isNull);
    expect(rest.calls, 0);
  });

  test('a DM resolution that outlives its session binds no contact and '
      "caches no peer into the next identity's memory", () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());
    await store.saveRoomMembers(
      'dm1',
      const ChatPaginatedResponse(
        items: [RoomUser(userId: 'me'), RoomUser(userId: 'bob')],
        hasMore: false,
        totalCount: 2,
      ),
    );
    await store.saveUsers([bob]);
    final roster = Completer<void>();
    store.rosterGate = roster;

    // The cache pass fires DM resolution and does NOT await it, so the
    // resolution is still parked on the roster read when the session ends.
    await enricher.loadAll();
    enricher.resetSession();
    roomList.setRooms(const []);

    roster.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Everything past the roster read writes into registries that outlive
    // the session: the contact→room map the next identity's DM lookups
    // read, and the user cache every row's title and avatar resolve
    // through. A peer of the account that just signed out has no business
    // in either.
    expect(dmContacts.roomIdFor('bob'), isNull);
    expect(knownUsers.containsKey('bob'), isFalse);
  });

  test('a session that ends between the roster read and the peer read '
      "keeps the peer out of the next identity's user cache", () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());
    await store.saveRoomMembers(
      'dm1',
      const ChatPaginatedResponse(
        items: [RoomUser(userId: 'me'), RoomUser(userId: 'bob')],
        hasMore: false,
        totalCount: 2,
      ),
    );
    await store.saveUsers([bob]);
    final peer = Completer<void>();
    store.userGate = peer;

    await enricher.loadAll();
    enricher.resetSession();
    roomList.setRooms(const []);

    peer.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The second half of the resolution has its own gate: the roster read
    // cleared while the session was still alive, so only the check AFTER
    // the profile read can stop Bob from landing in the user cache the
    // next account renders every row's title and avatar from.
    expect(knownUsers.containsKey('bob'), isFalse);
  });

  test('a session that ends while the DM resolutions are awaited does not '
      "then go shopping for the next identity's senders", () async {
    // No cache pass: this is the network leg, the only one that awaits its
    // DM resolutions and therefore the only one that can be interrupted
    // between the paint and the work that follows it.
    client.rooms.networkResult = ChatSuccess(seedDm());
    // The network leg names no policy, so `members.list` goes to the wire
    // rather than to the store — park it there.
    final roster = Completer<void>();
    rest.gate = roster;

    final outgoing = enricher.loadAll();
    await pumpEventQueue();
    enricher.resetSession();
    // User B signs in and their own list is on screen. Everything past the
    // DM wait iterates `roomList.allRooms` — which is now B's — so a pass
    // that keeps going fetches profiles for B's contacts under A's dead
    // session.
    roomList.setRooms(const [
      RoomListItem(id: 'b1', lastMessageUserId: 'carol', lastMessageId: 'm9'),
    ]);

    roster.complete();
    await outgoing;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(ensureUserCalls, isEmpty);
  });

  test('a roster on disk without the peer profile still binds the contact, '
      'so the row is no longer anonymous', () async {
    client.rooms.cacheResult = ChatSuccess(seedDm());
    await store.saveRoomMembers(
      'dm1',
      const ChatPaginatedResponse(
        items: [RoomUser(userId: 'me'), RoomUser(userId: 'bob')],
        hasMore: false,
        totalCount: 2,
      ),
    );

    await enricher.loadAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(roomList.getRoomById('dm1')!.otherUserId, 'bob');
    expect(rest.calls, 0);
  });
}
