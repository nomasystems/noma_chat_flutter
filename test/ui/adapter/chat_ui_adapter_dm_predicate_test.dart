import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

class _PredicateRoomsApi implements ChatRoomsApi {
  _PredicateRoomsApi(this._delegate, this._customByRoomId);

  final ChatRoomsApi _delegate;
  final Map<String, Map<String, dynamic>?> _customByRoomId;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final result = await _delegate.getUserRooms(
      type: type,
      pagination: pagination,
      cachePolicy: cachePolicy,
    );
    if (result.isFailure) return result;
    final userRooms = result.dataOrNull!;
    final dmRooms = userRooms.rooms
        .map(
          (r) => UnreadRoom(
            roomId: r.roomId,
            unreadMessages: r.unreadMessages,
            name: r.name,
            avatarUrl: r.avatarUrl,
            type: 'one-to-one',
            memberCount: r.memberCount,
          ),
        )
        .toList();
    return ChatSuccess(UserRooms(rooms: dmRooms));
  }

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    final base = await _delegate.get(roomId, cachePolicy: cachePolicy);
    if (base.isFailure) return base;
    final raw = base.dataOrNull!;
    return ChatSuccess(
      RoomDetail(
        id: raw.id,
        name: raw.name,
        subject: raw.subject,
        type: RoomType.oneToOne,
        memberCount: raw.memberCount,
        userRole: raw.userRole,
        config: raw.config,
        muted: raw.muted,
        pinned: raw.pinned,
        hidden: raw.hidden,
        createdAt: raw.createdAt,
        avatarUrl: raw.avatarUrl,
        custom: _customByRoomId[roomId],
      ),
    );
  }

  @override
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
  }) => _delegate.create(
    audience: audience,
    allowInvitations: allowInvitations,
    name: name,
    subject: subject,
    members: members,
    avatarUrl: avatarUrl,
    custom: custom,
    forceGroup: forceGroup,
  );

  @override
  Future<ChatResult<void>> delete(String roomId) => _delegate.delete(roomId);

  @override
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar = false,
    Map<String, dynamic>? custom,
  }) => _delegate.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    clearAvatar: clearAvatar,
    custom: custom,
  );

  @override
  Future<ChatResult<RoomPreferences>> patchPreferences(
    String roomId, {
    bool? muted,
    DateTime? muteUntil,
    bool? pinned,
    bool? hidden,
  }) => _delegate.patchPreferences(
    roomId,
    muted: muted,
    muteUntil: muteUntil,
    pinned: pinned,
    hidden: hidden,
  );

  @override
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds) =>
      _delegate.batchMarkAsRead(roomIds);

  @override
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      _delegate.batchGetUnread(roomIds);

  @override
  Future<void> updateCachedRoomPreview(
    String roomId, {
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    bool? lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
  }) => _delegate.updateCachedRoomPreview(
    roomId,
    lastMessage: lastMessage,
    lastMessageTime: lastMessageTime,
    lastMessageUserId: lastMessageUserId,
    lastMessageId: lastMessageId,
    lastMessageType: lastMessageType,
    lastMessageMimeType: lastMessageMimeType,
    lastMessageFileName: lastMessageFileName,
    lastMessageDurationMs: lastMessageDurationMs,
    lastMessageIsDeleted: lastMessageIsDeleted,
    lastMessageReactionEmoji: lastMessageReactionEmoji,
  );
}

class _PredicateTestClient implements ChatClient {
  _PredicateTestClient(
    this._delegate,
    Map<String, Map<String, dynamic>?> custom,
  ) : _rooms = _PredicateRoomsApi(_delegate.rooms, custom);

  final MockChatClient _delegate;
  final _PredicateRoomsApi _rooms;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _rooms;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;
  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
}

void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  Future<({MockChatClient mock, ChatUiAdapter adapter})> setupAdapter({
    required Map<String, Map<String, dynamic>?> customByRoomId,
    IsDmRoomPredicate? isDmRoom,
  }) async {
    final mock = MockChatClient(currentUserId: 'u1');
    final client = _PredicateTestClient(mock, customByRoomId);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      isDmRoom: isDmRoom,
    );
    return (mock: mock, adapter: adapter);
  }

  group('isDmRoom predicate', () {
    test('without predicate, nameless oneToOne room enters DM cache '
        '(default behaviour)', () async {
      final s = await setupAdapter(customByRoomId: {});
      // a real DM has no user-assigned name. Rooms with a
      // name are intentional groups (even with 2 members) and the
      // default `_isDmDetail` excludes them from the DM cache, so
      // create the DM with no name here.
      await s.mock.rooms.create(
        audience: RoomAudience.contacts,
        members: ['u2'],
      );

      final result = await s.adapter.rooms.load();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      final room = s.adapter.roomListController.allRooms.first;
      expect(s.adapter.dm.getRoomId('u2'), room.id);

      await s.adapter.dispose();
      await s.mock.dispose();
    });

    test('without predicate, NAMED 2-member oneToOne room does NOT enter DM '
        'cache', () async {
      final s = await setupAdapter(customByRoomId: {});
      await s.mock.rooms.create(
        audience: RoomAudience.contacts,
        name: 'A&B private group',
        members: ['u2'],
      );

      final result = await s.adapter.rooms.load();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      // The room is in the list (the user sees their group)…
      expect(s.adapter.roomListController.allRooms.length, 1);
      // …but it is NOT registered as a DM with u2, so the user can
      // still openDirectMessageDraft with u2 in a separate flow.
      expect(s.adapter.dm.getRoomId('u2'), isNull);

      await s.adapter.dispose();
      await s.mock.dispose();
    });

    test(
      'with predicate, oneToOne room with non-dm custom does NOT enter cache',
      () async {
        final mock = MockChatClient(currentUserId: 'u1');
        final created = await mock.rooms.create(
          audience: RoomAudience.contacts,
          name: 'Plan room',
          members: ['u2'],
        );
        final roomId = created.dataOrNull!.id;
        final customByRoomId = <String, Map<String, dynamic>?>{
          roomId: {'type': 'plan_group'},
        };
        final client = _PredicateTestClient(mock, customByRoomId);
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: currentUser,
          isDmRoom: (d) =>
              d.type == RoomType.oneToOne && d.custom?['type'] == 'dm',
        );

        final result = await adapter.rooms.load();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(result.isSuccess, true);
        expect(adapter.dm.getRoomId('u2'), isNull);
        final room = adapter.roomListController.allRooms.first;
        expect(room.otherUserId, isNull);

        await adapter.dispose();
        await mock.dispose();
      },
    );

    test(
      'with predicate, oneToOne room with dm custom DOES enter cache',
      () async {
        final mock = MockChatClient(currentUserId: 'u1');
        final created = await mock.rooms.create(
          audience: RoomAudience.contacts,
          name: 'DM room',
          members: ['u2'],
        );
        final roomId = created.dataOrNull!.id;
        final customByRoomId = <String, Map<String, dynamic>?>{
          roomId: {'type': 'dm'},
        };
        final client = _PredicateTestClient(mock, customByRoomId);
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: currentUser,
          isDmRoom: (d) =>
              d.type == RoomType.oneToOne && d.custom?['type'] == 'dm',
        );

        final result = await adapter.rooms.load();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(result.isSuccess, true);
        expect(adapter.dm.getRoomId('u2'), roomId);
        final room = adapter.roomListController.allRooms.first;
        expect(room.otherUserId, 'u2');

        await adapter.dispose();
        await mock.dispose();
      },
    );
  });
}
