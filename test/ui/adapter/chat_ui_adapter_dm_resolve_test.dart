import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _FailableMembersApi implements ChatMembersApi {
  final ChatMembersApi _delegate;
  _FailableMembersApi(this._delegate);

  bool failList = false;
  bool throwOnList = false;

  @override
  Future<Result<PaginatedResponse<RoomUser>>> list(
    String roomId, {
    PaginationParams? pagination,
  }) {
    if (throwOnList) throw StateError('members.list threw synchronously');
    if (failList) {
      return Future.value(const Failure(ServerFailure(statusCode: 500)));
    }
    return _delegate.list(roomId, pagination: pagination);
  }

  @override
  Future<Result<void>> add(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  }) => _delegate.add(roomId, userIds: userIds, mode: mode, userRole: userRole);

  @override
  Future<Result<void>> remove(String roomId, String userId) =>
      _delegate.remove(roomId, userId);

  @override
  Future<Result<void>> leave(String roomId) => _delegate.leave(roomId);

  @override
  Future<Result<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => _delegate.updateRole(roomId, userId, role);

  @override
  Future<Result<void>> ban(String roomId, String userId, {String? reason}) =>
      _delegate.ban(roomId, userId, reason: reason);

  @override
  Future<Result<void>> unban(String roomId, String userId) =>
      _delegate.unban(roomId, userId);

  @override
  Future<Result<void>> muteUser(String roomId, String userId) =>
      _delegate.muteUser(roomId, userId);

  @override
  Future<Result<void>> unmuteUser(String roomId, String userId) =>
      _delegate.unmuteUser(roomId, userId);
}

class _DmRoomsApi implements ChatRoomsApi {
  final ChatRoomsApi _delegate;
  _DmRoomsApi(this._delegate);

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
    return Success(UserRooms(rooms: dmRooms));
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
  }) => _delegate.create(
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
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    PaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<Result<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    final base = await _delegate.get(roomId, cachePolicy: cachePolicy);
    if (base.isFailure) return base;
    final raw = base.dataOrNull!;
    return Success(
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
        custom: raw.custom,
      ),
    );
  }

  @override
  Future<Result<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => _delegate.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    custom: custom,
  );

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

class _DmTestClient implements ChatClient {
  final MockChatClient _delegate;
  late final _FailableMembersApi _failableMembers;
  late final _DmRoomsApi _dmRooms;

  _DmTestClient(this._delegate) {
    _failableMembers = _FailableMembersApi(_delegate.members);
    _dmRooms = _DmRoomsApi(_delegate.rooms);
  }

  _FailableMembersApi get failableMembers => _failableMembers;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _dmRooms;
  @override
  ChatMembersApi get members => _failableMembers;
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
  late MockChatClient mockClient;
  late _DmTestClient testClient;
  late ChatUiAdapter adapter;

  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    testClient = _DmTestClient(mockClient);
    adapter = ChatUiAdapter(client: testClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('_resolveDmContact resilience', () {
    test('loadRooms succeeds when members.list returns failure', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'DM Room',
        members: ['u2'],
      );

      testClient.failableMembers.failList = true;
      final result = await adapter.loadRooms();

      expect(result.isSuccess, true);
      expect(adapter.roomListController.allRooms, hasLength(1));
    });

    test('loadRooms succeeds when members.list throws', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'DM Room',
        members: ['u2'],
      );

      testClient.failableMembers.throwOnList = true;
      final result = await adapter.loadRooms();

      expect(result.isSuccess, true);
      expect(adapter.roomListController.allRooms, hasLength(1));
    });

    test('DM contact is not resolved when members.list fails', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'DM Room',
        members: ['u2'],
      );

      testClient.failableMembers.failList = true;
      await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 50));

      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, isNull);
    });

    test('DM contact is resolved when members.list succeeds', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'DM Room',
        members: ['u2'],
      );

      final result = await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, 'u2');
    });
  });
}
