import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// Answers `getUserRooms`/`get` from a fixed script instead of the real
/// listing/detail machinery, so a test can hand the enricher an exact
/// `UnreadRoom.custom` and/or `RoomDetail.custom` without the mock's own
/// `getUserRooms` (which never sets `custom` on the listing row) getting in
/// the way. Every other member delegates to the real mock client.
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  UserRooms userRooms = const UserRooms(rooms: []);

  /// When set, every `get` answers this instead of asking the delegate —
  /// the "a fresh detail landed" case. Left `null` means "no detail
  /// available", the same as a room the mock never seeded.
  ChatResult<RoomDetail>? detailOverride;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async => ChatSuccess(userRooms);

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) => detailOverride != null
      ? Future.value(detailOverride)
      : _delegate.get(roomId, cachePolicy: cachePolicy);

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedClient implements ChatClient {
  _ScriptedClient(this._delegate) : rooms = _ScriptedRoomsApi(_delegate.rooms);

  final MockChatClient _delegate;

  @override
  final _ScriptedRoomsApi rooms;

  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  MockPresenceApi get presence => _delegate.presence;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _ScriptedClient client;
  late RoomListController roomList;
  late DmContactRegistry dmContacts;
  late RoomEnricher enricher;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _ScriptedClient(mock);
    roomList = RoomListController();
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
      findCachedUser: (_) => null,
      cacheUsers: (_) {},
      ensureUserCached: (_) async {},
      updateRoomLastMessage: (_, _) {},
      removeChatController: (_) {},
    );
  });

  tearDown(() async {
    enricher.dispose();
    roomList.dispose();
    await mock.dispose();
  });

  test('a listing pass with no fresh detail conserves the custom the '
      'listing itself carried', () async {
    client.rooms.userRooms = const UserRooms(
      rooms: [
        UnreadRoom(roomId: 'r1', unreadMessages: 0, custom: {'support': true}),
      ],
    );
    // No room seeded on the mock ⇒ `client.rooms.get('r1')` (still routed
    // to the real mock via `_delegate`) answers `NotFoundFailure`, exactly
    // like a cold start off cache or an offline detail fetch.

    await enricher.hydrateFromCache();

    final row = roomList.getRoomById('r1');
    expect(row, isNotNull);
    expect(row!.custom, {'support': true});
  });

  test(
    'a fresh room detail overrides the custom the listing snapshot carried',
    () async {
      client.rooms.userRooms = const UserRooms(
        rooms: [
          UnreadRoom(
            roomId: 'r1',
            unreadMessages: 0,
            custom: {'support': true},
          ),
        ],
      );
      client.rooms.detailOverride = const ChatSuccess(
        RoomDetail(
          id: 'r1',
          type: RoomType.group,
          memberCount: 3,
          userRole: RoomRole.member,
          config: RoomConfig(),
          custom: {'support': false, 'nickname': 'Team'},
        ),
      );

      await enricher.hydrateFromCache();

      final row = roomList.getRoomById('r1');
      expect(row, isNotNull);
      expect(row!.custom, {'support': false, 'nickname': 'Team'});
    },
  );

  test('a room with no fresh detail and no listing custom keeps whatever this '
      'room already had painted', () async {
    // First pass: a fresh detail paints `custom`.
    client.rooms.userRooms = const UserRooms(
      rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
    );
    client.rooms.detailOverride = const ChatSuccess(
      RoomDetail(
        id: 'r1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.member,
        config: RoomConfig(),
        custom: {'support': true},
      ),
    );
    await enricher.hydrateFromCache();
    expect(roomList.getRoomById('r1')!.custom, {'support': true});

    // Second pass: neither the detail nor the listing snapshot carries
    // `custom` any more (e.g. a stale cache read) — the row must not be
    // blanked.
    client.rooms.detailOverride = null;
    mock.seedRoom(const ChatRoom(id: 'r1'));
    await enricher.hydrateFromCache();

    expect(roomList.getRoomById('r1')!.custom, {'support': true});
  });

  test('a kicked-room stub rebuilt from cache conserves the custom the '
      'cached room carried', () async {
    final cache = MemoryChatLocalDatasource();
    await cache.markKicked('k1');
    await cache.saveRooms(const [
      ChatRoom(id: 'k1', name: 'Kicked room', custom: {'support': true}),
    ]);
    await cache.saveUnreads(const [
      UnreadRoom(roomId: 'k1', unreadMessages: 0),
    ]);
    final withCache = RoomEnricher(
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
      cache: cache,
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
      removeChatController: (_) {},
    );
    addTearDown(withCache.dispose);
    mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
    client.rooms.userRooms = const UserRooms(
      rooms: [UnreadRoom(roomId: 'a1', unreadMessages: 0)],
    );

    await withCache.loadAll();
    await pumpEventQueue();

    final kicked = roomList.rooms.where((r) => r.id == 'k1').single;
    expect(kicked.isParticipating, isFalse);
    expect(kicked.custom, {'support': true});
  });
}
