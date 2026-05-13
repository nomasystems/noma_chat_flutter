import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _PredicateRoomsApi implements ChatRoomsApi {
  _PredicateRoomsApi(this._delegate, this._customByRoomId);

  final ChatRoomsApi _delegate;
  final Map<String, Map<String, dynamic>?> _customByRoomId;

  @override
  Future<Result<UserRooms>> getUserRooms({
    String type = 'all',
    PaginationParams? pagination,
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
        .map((r) => UnreadRoom(
              roomId: r.roomId,
              unreadMessages: r.unreadMessages,
              name: r.name,
              avatarUrl: r.avatarUrl,
              type: 'one-to-one',
              memberCount: r.memberCount,
            ))
        .toList();
    return Success(UserRooms(rooms: dmRooms));
  }

  @override
  Future<Result<RoomDetail>> get(String roomId,
      {CachePolicy? cachePolicy}) async {
    final base = await _delegate.get(roomId, cachePolicy: cachePolicy);
    if (base.isFailure) return base;
    final raw = base.dataOrNull!;
    return Success(RoomDetail(
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
    ));
  }

  @override
  Future<Result<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) =>
      _delegate.create(
        audience: audience,
        allowInvitations: allowInvitations,
        name: name,
        subject: subject,
        members: members,
        avatarUrl: avatarUrl,
        custom: custom,
      );

  @override
  Future<Result<void>> delete(String roomId) => _delegate.delete(roomId);

  @override
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(String query,
          {PaginationParams? pagination}) =>
      _delegate.discover(query, pagination: pagination);

  @override
  Future<Result<void>> updateConfig(String roomId,
          {String? name,
          String? subject,
          String? avatarUrl,
          Map<String, dynamic>? custom}) =>
      _delegate.updateConfig(roomId,
          name: name,
          subject: subject,
          avatarUrl: avatarUrl,
          custom: custom);

  @override
  Future<Result<void>> mute(String roomId) => _delegate.mute(roomId);

  @override
  Future<Result<void>> unmute(String roomId) => _delegate.unmute(roomId);

  @override
  Future<Result<void>> pin(String roomId) => _delegate.pin(roomId);

  @override
  Future<Result<void>> unpin(String roomId) => _delegate.unpin(roomId);

  @override
  Future<Result<void>> batchMarkAsRead(List<String> roomIds) =>
      _delegate.batchMarkAsRead(roomIds);

  @override
  Future<Result<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      _delegate.batchGetUnread(roomIds);

  @override
  Future<Result<void>> hide(String roomId) => _delegate.hide(roomId);

  @override
  Future<Result<void>> unhide(String roomId) => _delegate.unhide(roomId);

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
  }) =>
      _delegate.updateCachedRoomPreview(
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
  _PredicateTestClient(this._delegate, Map<String, Map<String, dynamic>?> custom)
      : _rooms = _PredicateRoomsApi(_delegate.rooms, custom);

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
    test('without predicate, oneToOne room enters DM cache (default behaviour)',
        () async {
      final s = await setupAdapter(customByRoomId: {});
      await s.mock.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Plain DM',
        members: ['u2'],
      );

      final result = await s.adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      final room = s.adapter.roomListController.allRooms.first;
      expect(s.adapter.getDmRoomId('u2'), room.id);

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

      final result = await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      expect(adapter.getDmRoomId('u2'), isNull);
      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, isNull);

      await adapter.dispose();
      await mock.dispose();
    });

    test('with predicate, oneToOne room with dm custom DOES enter cache',
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

      final result = await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      expect(adapter.getDmRoomId('u2'), roomId);
      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, 'u2');

      await adapter.dispose();
      await mock.dispose();
    });
  });
}
