import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

class _FailableMembersApi implements ChatMembersApi {
  final ChatMembersApi _delegate;
  _FailableMembersApi(this._delegate);

  bool failList = false;
  bool throwOnList = false;

  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
  }) {
    if (throwOnList) throw StateError('members.list threw synchronously');
    if (failList) {
      return Future.value(
        const ChatFailureResult(ServerFailure(statusCode: 500)),
      );
    }
    return _delegate.list(roomId, pagination: pagination, expand: expand);
  }

  @override
  Future<ChatResult<InviteResult>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    String? token,
  }) => _delegate.invite(roomId, userIds: userIds, mode: mode, token: token);

  @override
  Future<ChatResult<InviteResult>> joinWithToken(
    String roomId, {
    required String token,
  }) => _delegate.joinWithToken(roomId, token: token);

  @override
  Future<ChatResult<void>> remove(String roomId, String userId) =>
      _delegate.remove(roomId, userId);

  @override
  Future<ChatResult<void>> leave(String roomId) => _delegate.leave(roomId);

  @override
  Future<ChatResult<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => _delegate.updateRole(roomId, userId, role);

  @override
  Future<ChatResult<void>> ban(
    String roomId,
    String userId, {
    String? reason,
  }) => _delegate.ban(roomId, userId, reason: reason);

  @override
  Future<ChatResult<void>> unban(String roomId, String userId) =>
      _delegate.unban(roomId, userId);

  @override
  Future<ChatResult<void>> muteUser(String roomId, String userId) =>
      _delegate.muteUser(roomId, userId);

  @override
  Future<ChatResult<void>> unmuteUser(String roomId, String userId) =>
      _delegate.unmuteUser(roomId, userId);
}

class _DmRoomsApi implements ChatRoomsApi {
  final ChatRoomsApi _delegate;
  _DmRoomsApi(this._delegate);

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
        custom: raw.custom,
      ),
    );
  }

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

  @override
  Future<ChatResult<void>> markRoomDeleted(String roomId) =>
      _delegate.markRoomDeleted(roomId);

  @override
  Future<ChatResult<void>> clearRoomDeleted(String roomId) =>
      _delegate.clearRoomDeleted(roomId);

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();
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
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _delegate.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

void main() {
  late MockChatClient mockClient;
  late _DmTestClient testClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

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
      // real DMs have no user-assigned name. Rooms with a
      // name are intentional groups (even with 2 members) and the
      // default `_isDmDetail` excludes them from DM resolution.
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        members: ['u2'],
      );

      testClient.failableMembers.failList = true;
      final result = await adapter.rooms.load();

      expect(result.isSuccess, true);
      expect(adapter.roomListController.allRooms, hasLength(1));
    });

    test('loadRooms succeeds when members.list throws', () async {
      // real DMs have no user-assigned name. Rooms with a
      // name are intentional groups (even with 2 members) and the
      // default `_isDmDetail` excludes them from DM resolution.
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        members: ['u2'],
      );

      testClient.failableMembers.throwOnList = true;
      final result = await adapter.rooms.load();

      expect(result.isSuccess, true);
      expect(adapter.roomListController.allRooms, hasLength(1));
    });

    test('DM contact is not resolved when members.list fails', () async {
      // real DMs have no user-assigned name. Rooms with a
      // name are intentional groups (even with 2 members) and the
      // default `_isDmDetail` excludes them from DM resolution.
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        members: ['u2'],
      );

      testClient.failableMembers.failList = true;
      await adapter.rooms.load();
      await Future.delayed(const Duration(milliseconds: 50));

      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, isNull);
    });

    test('DM contact is resolved when members.list succeeds', () async {
      // real DMs have no user-assigned name. Rooms with a
      // name are intentional groups (even with 2 members) and the
      // default `_isDmDetail` excludes them from DM resolution.
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        members: ['u2'],
      );

      final result = await adapter.rooms.load();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(result.isSuccess, true);
      final room = adapter.roomListController.allRooms.first;
      expect(room.otherUserId, 'u2');
    });
  });
}
