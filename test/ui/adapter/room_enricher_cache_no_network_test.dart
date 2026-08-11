import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// Answers `getUserRooms` from a script so the cache phase and the network
/// phase of [RoomEnricher.loadAll] can be driven independently: a failing
/// `networkResult` isolates the cache pass, a failing `cacheResult`
/// isolates the network pass. Every other member delegates to the mock.
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

/// Counts the three REST reads the cache phase used to emit, so a test can
/// assert on "did this pass touch the wire" rather than on timing.
class _CountingMembersApi implements ChatMembersApi {
  _CountingMembersApi(this._delegate);
  final ChatMembersApi _delegate;
  int listCalls = 0;

  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
  }) {
    listCalls++;
    return _delegate.list(roomId, pagination: pagination, expand: expand);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingUsersApi implements ChatUsersApi {
  _CountingUsersApi(this._delegate);
  final ChatUsersApi _delegate;
  final List<CachePolicy?> getPolicies = [];

  @override
  Future<ChatResult<ChatUser>> get(String userId, {CachePolicy? cachePolicy}) {
    getPolicies.add(cachePolicy);
    return _delegate.get(userId, cachePolicy: cachePolicy);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedClient implements ChatClient {
  _ScriptedClient(this._delegate)
    : rooms = _ScriptedRoomsApi(_delegate.rooms),
      members = _CountingMembersApi(_delegate.members),
      users = _CountingUsersApi(_delegate.users);

  final MockChatClient _delegate;

  @override
  final _ScriptedRoomsApi rooms;
  @override
  final _CountingMembersApi members;
  @override
  final _CountingUsersApi users;

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
  late RoomListController roomList;
  late RoomEnricher enricher;
  late DmContactRegistry dmContacts;

  /// Users the enricher's in-memory lookup knows about. Mirrors the
  /// adapter's user cache without pulling the adapter in.
  late Map<String, ChatUser> knownUsers;

  /// Every `confirmDelivered(roomId, messageId)` the enricher asked for.
  late List<String> deliveredCursors;

  /// Every `ensureUserCached(userId)` the enricher asked for.
  late List<String> hydratedSenders;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _ScriptedClient(mock);
    roomList = RoomListController();
    dmContacts = DmContactRegistry();
    knownUsers = {};
    deliveredCursors = [];
    hydratedSenders = [];
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
      ensureUserCached: (id) async => hydratedSenders.add(id),
      updateRoomLastMessage: (_, _) {},
      removeChatController: (_) {},
      confirmDelivered: (roomId, messageId) async {
        deliveredCursors.add('$roomId:$messageId');
        return const ChatSuccess(null);
      },
    );
  });

  tearDown(() async {
    enricher.dispose();
    roomList.dispose();
    await mock.dispose();
  });

  /// A DM with Bob plus a group, both with an unread message from someone
  /// the user cache has never heard of — the shape that made the cache
  /// pass emit one `members.list`, one `users.get`, one
  /// `markRoomAsDelivered` and one sender hydration per room.
  UserRooms seedTwoRoomsWithBacklog() {
    mock.seedRoom(const ChatRoom(id: 'dm1', members: ['me', 'bob']));
    mock.seedRoom(
      const ChatRoom(id: 'g1', name: 'Group', members: ['me', 'bob', 'zoe']),
    );
    mock.seedUser(bob);
    mock.seedUser(const ChatUser(id: 'zoe', displayName: 'Zoe'));
    return UserRooms(
      rooms: [
        UnreadRoom(
          roomId: 'dm1',
          unreadMessages: 2,
          lastMessage: 'hola',
          lastMessageId: 'm1',
          lastMessageUserId: 'bob',
          lastMessageTime: DateTime.utc(2026, 1, 1),
        ),
        UnreadRoom(
          roomId: 'g1',
          unreadMessages: 1,
          lastMessage: 'buenas',
          lastMessageId: 'm2',
          lastMessageUserId: 'zoe',
          lastMessageTime: DateTime.utc(2026, 1, 2),
        ),
      ],
    );
  }

  group('the cache pass never touches the network', () {
    setUp(() {
      client.rooms.cacheResult = ChatSuccess(seedTwoRoomsWithBacklog());
      // The network pass fails at the listing, so every counter below can
      // only have been moved by the cache pass.
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );
    });

    test('does not bootstrap presence — that GET was awaited, so offline it '
        'parked the first paint behind a whole timeout', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.presence.getAllCallCount, 0);
    });

    test('does not confirm delivery — one POST per unread room, claiming a '
        'receipt taken from disk rather than from the server', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(deliveredCursors, isEmpty);
    });

    test('does not hydrate unknown last-message senders — one REST read '
        'each, for a name the row cannot show yet anyway', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(hydratedSenders, isEmpty);
    });

    test('does not resolve DM contacts — `members.list` has no cache path, '
        'so each DM would be a mandatory request', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.members.listCalls, 0);
      expect(client.users.getPolicies, isEmpty);
    });

    test('still paints every cached row', () async {
      await enricher.loadAll();

      expect(roomList.allRooms.map((r) => r.id), containsAll(['dm1', 'g1']));
    });
  });

  group('a DM the session already resolved survives the cache pass', () {
    test('keeps its peer, title and avatar without a single request', () async {
      client.rooms.cacheResult = ChatSuccess(seedTwoRoomsWithBacklog());
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );
      // State a previous (network) pass would have left behind.
      dmContacts.bind('bob', 'dm1');
      knownUsers['bob'] = bob;

      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final row = roomList.getRoomById('dm1')!;
      expect(row.otherUserId, 'bob');
      expect(row.displayName, 'Bob');
      expect(row.avatarUrl, 'https://cdn/bob.png');
      expect(client.members.listCalls, 0);
      expect(client.users.getPolicies, isEmpty);
    });

    test('a warm reopen does not blank the row it just painted', () async {
      client.rooms.cacheResult = ChatSuccess(seedTwoRoomsWithBacklog());
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );
      dmContacts.bind('bob', 'dm1');
      knownUsers['bob'] = bob;
      await enricher.loadAll();

      // Second open: `mergeRooms` replaces rows wholesale, so a cache pass
      // that rebuilt the DM row from the bare cached detail would
      // overwrite the resolved one with an untitled placeholder.
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final row = roomList.getRoomById('dm1')!;
      expect(row.otherUserId, 'bob');
      expect(row.displayName, 'Bob');
    });
  });

  group('the network pass still does all of it', () {
    setUp(() {
      // Cache unreadable → the cache phase is skipped entirely and every
      // counter below reflects the network pass alone.
      client.rooms.cacheResult = const ChatFailureResult(
        UnexpectedFailure('cache unreadable'),
      );
      client.rooms.networkResult = ChatSuccess(seedTwoRoomsWithBacklog());
    });

    test('bootstraps presence, confirms delivery, hydrates senders and '
        'resolves DM contacts', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.presence.getAllCallCount, 1);
      expect(deliveredCursors, unorderedEquals(['dm1:m1', 'g1:m2']));
      expect(hydratedSenders, containsAll(['bob', 'zoe']));
      expect(client.members.listCalls, 1);
      expect(roomList.getRoomById('dm1')!.otherUserId, 'bob');
      expect(roomList.getRoomById('dm1')!.displayName, 'Bob');
    });

    test('reads the DM peer with an explicit cacheFirst policy instead of '
        'falling through to the networkFirst default', () async {
      await enricher.loadAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.users.getPolicies, [CachePolicy.cacheFirst]);
    });
  });
}
