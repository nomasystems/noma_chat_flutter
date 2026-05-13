import 'dart:async';
import 'dart:typed_data';

import '../_internal/cache/cache_policy.dart';
import '../client/chat_client.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/attachment.dart';
import '../models/contact.dart';
import '../models/health_status.dart';
import '../models/managed_user_config.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/presence.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/report.dart';
import '../models/room.dart';
import '../models/room_user.dart';
import '../models/scheduled_message.dart';
import '../models/unread_room.dart';
import '../models/user.dart';
import '../models/user_rooms.dart';

/// In-memory [ChatClient] for testing and prototyping without a backend.
///
/// Stores rooms, users, and messages locally. Events are emitted synchronously
/// when messages are sent. Use [emitEvent] to simulate server-side events.
class MockChatClient implements ChatClient {
  final String currentUserId;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();
  ChatConnectionState _connectionState = ChatConnectionState.disconnected;

  final Map<String, ChatUser> _users = {};
  final Map<String, ChatRoom> _rooms = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final List<String> _contacts = [];
  int _messageCounter = 0;

  @override
  late final MockAuthApi auth;
  @override
  late final MockUsersApi users;
  @override
  late final MockRoomsApi rooms;
  @override
  late final MockMembersApi members;
  @override
  late final MockMessagesApi messages;
  @override
  late final MockContactsApi contacts;
  @override
  late final MockPresenceApi presence;
  @override
  late final MockAttachmentsApi attachments;

  MockChatClient({required this.currentUserId}) {
    _users[currentUserId] = ChatUser(
      id: currentUserId,
      displayName: 'Mock User',
      active: true,
    );
    auth = MockAuthApi();
    users = MockUsersApi(this);
    rooms = MockRoomsApi(this);
    members = MockMembersApi(this);
    messages = MockMessagesApi(this);
    contacts = MockContactsApi(this);
    presence = MockPresenceApi(currentUserId);
    attachments = MockAttachmentsApi();
  }

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  ChatConnectionState get connectionState => _connectionState;

  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;

  @override
  Future<void> connect() async {
    _connectionState = ChatConnectionState.connected;
    _stateController.add(_connectionState);
    _eventController.add(const ChatEvent.connected());
  }

  @override
  Future<void> disconnect() async {
    _connectionState = ChatConnectionState.disconnected;
    _stateController.add(_connectionState);
    _eventController.add(const ChatEvent.disconnected());
  }

  @override
  Future<void> notifyTokenRotated() async {}

  void emitEvent(ChatEvent event) => _eventController.add(event);

  /// Test helper: register a room directly in the mock store so subsequent
  /// `client.rooms.get(roomId)` calls return a proper `RoomDetail`.
  void seedRoom(ChatRoom room) {
    _rooms[room.id] = room;
    _messages.putIfAbsent(room.id, () => []);
  }

  void addMessage(String roomId, ChatMessage message) {
    _messages.putIfAbsent(roomId, () => []);
    final existing = _messages[roomId]!.indexWhere((m) => m.id == message.id);
    if (existing >= 0) {
      _messages[roomId]![existing] = message;
    } else {
      _messages[roomId]!.insert(0, message);
    }
  }

  String _nextMessageId() => 'mock-msg-${++_messageCounter}';

  @override
  Future<void> logout() async {
    await disconnect();
    _rooms.clear();
    _messages.clear();
    _contacts.clear();
    _users.clear();
  }

  @override
  Future<void> dispose() async {
    await _eventController.close();
    await _stateController.close();
  }
}

class MockAuthApi implements ChatAuthApi {
  @override
  Future<Result<HealthStatus>> healthCheck() async =>
      const Success(HealthStatus(status: ServiceStatus.ok));
}

class MockUsersApi implements ChatUsersApi {
  final MockChatClient _client;
  MockUsersApi(this._client);

  @override
  Future<Result<ChatUser>> get(String userId, {CachePolicy? cachePolicy}) async {
    final user = _client._users[userId];
    if (user == null) return const Failure(NotFoundFailure());
    return Success(user);
  }

  @override
  Future<Result<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
  }) async {
    final id = 'mock-user-${_client._users.length}';
    final user = ChatUser(id: id, active: true);
    _client._users[id] = user;
    return Success(user);
  }

  @override
  Future<Result<PaginatedResponse<ChatUser>>> search(String query,
      {PaginationParams? pagination}) async {
    final matches = _client._users.values
        .where((u) =>
            u.displayName?.toLowerCase().contains(query.toLowerCase()) ??
            false)
        .toList();
    return Success(PaginatedResponse(items: matches, hasMore: false));
  }

  @override
  Future<Result<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  }) async {
    final existing = _client._users[userId];
    if (existing == null) return const Failure(NotFoundFailure());
    final updated = ChatUser(
      id: userId,
      displayName: displayName ?? existing.displayName,
      avatarUrl: avatarUrl ?? existing.avatarUrl,
      bio: bio ?? existing.bio,
      email: email ?? existing.email,
      custom: custom ?? existing.custom,
      active: active ?? existing.active,
      role: existing.role,
      configuration: existing.configuration,
    );
    _client._users[userId] = updated;
    return Success(updated);
  }

  @override
  Future<Result<void>> delete(String userId) async {
    if (!_client._users.containsKey(userId)) {
      return const Failure(NotFoundFailure());
    }
    _client._users.remove(userId);
    return const Success(null);
  }

  @override
  Future<Result<ChatUser>> searchManaged({required String externalId}) async =>
      const Failure(NotFoundFailure());

  @override
  Future<Result<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  }) async =>
      const Success([]);

  @override
  Future<Result<PaginatedResponse<ChatUser>>> getManaged(
    String userId, {
    PaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  }) async =>
      const Success(null);

  @override
  Future<Result<ManagedUserConfiguration>> getManagedConfig(
          String userId) async =>
      const Success(UserConfiguration());

  @override
  Future<Result<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  }) async =>
      const Success(null);
}

class MockRoomsApi implements ChatRoomsApi {
  final MockChatClient _client;
  MockRoomsApi(this._client);

  @override
  Future<Result<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) async {
    final id = 'mock-room-${_client._rooms.length}';
    final room = ChatRoom(
      id: id,
      owner: _client.currentUserId,
      name: name,
      subject: subject,
      audience: audience,
      allowInvitations: allowInvitations,
      members: [_client.currentUserId, ...?members],
      avatarUrl: avatarUrl,
      custom: custom,
    );
    _client._rooms[id] = room;
    _client._messages[id] = [];
    return Success(room);
  }

  @override
  Future<Result<UserRooms>> getUserRooms({
    String type = 'all',
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final rooms = _client._rooms.values
        .map((r) => UnreadRoom(
              roomId: r.id,
              unreadMessages: 0,
              name: r.name,
              avatarUrl: r.avatarUrl,
              type: r.audience == RoomAudience.public ? 'group' : 'group',
              memberCount: r.members.length,
            ))
        .toList();
    return Success(UserRooms(rooms: rooms));
  }

  @override
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    PaginationParams? pagination,
  }) async {
    final matches = _client._rooms.values
        .where((r) =>
            r.name?.toLowerCase().contains(query.toLowerCase()) ?? false)
        .map((r) => DiscoveredRoom(id: r.id, name: r.name, subject: r.subject))
        .toList();
    return Success(PaginatedResponse(items: matches, hasMore: false));
  }

  @override
  Future<Result<RoomDetail>> get(String roomId, {CachePolicy? cachePolicy}) async {
    final room = _client._rooms[roomId];
    if (room == null) return const Failure(NotFoundFailure());
    return Success(RoomDetail(
      id: room.id,
      name: room.name,
      subject: room.subject,
      type: RoomType.group,
      memberCount: room.members.length,
      userRole: RoomRole.owner,
      config: RoomConfig(allowInvitations: room.allowInvitations),
    ));
  }

  @override
  Future<Result<void>> delete(String roomId) async {
    if (!_client._rooms.containsKey(roomId)) {
      return const Failure(NotFoundFailure());
    }
    _client._rooms.remove(roomId);
    _client._messages.remove(roomId);
    return const Success(null);
  }

  @override
  Future<Result<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const Failure(NotFoundFailure());
    _client._rooms[roomId] = ChatRoom(
      id: room.id,
      owner: room.owner,
      name: name ?? room.name,
      subject: subject ?? room.subject,
      audience: room.audience,
      allowInvitations: room.allowInvitations,
      members: room.members,
      avatarUrl: avatarUrl ?? room.avatarUrl,
      custom: custom ?? room.custom,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> mute(String roomId) async => const Success(null);

  @override
  Future<Result<void>> unmute(String roomId) async => const Success(null);

  @override
  Future<Result<void>> pin(String roomId) async => const Success(null);

  @override
  Future<Result<void>> unpin(String roomId) async => const Success(null);

  @override
  Future<Result<void>> hide(String roomId) async => const Success(null);

  @override
  Future<Result<void>> unhide(String roomId) async => const Success(null);

  @override
  Future<Result<void>> batchMarkAsRead(List<String> roomIds) async =>
      const Success(null);

  @override
  Future<Result<List<UnreadRoom>>> batchGetUnread(
          List<String> roomIds) async =>
      Success(roomIds
          .map((id) => UnreadRoom(roomId: id, unreadMessages: 0))
          .toList());

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
  }) async {}
}

class MockMembersApi implements ChatMembersApi {
  final MockChatClient _client;
  MockMembersApi(this._client);

  @override
  Future<Result<PaginatedResponse<RoomUser>>> list(String roomId,
      {PaginationParams? pagination}) async {
    final room = _client._rooms[roomId];
    if (room == null) return const Failure(NotFoundFailure());
    final users =
        room.members.map((id) => RoomUser(userId: id)).toList();
    return Success(PaginatedResponse(items: users, hasMore: false));
  }

  @override
  Future<Result<void>> add(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const Failure(NotFoundFailure());
    _client._rooms[roomId] = ChatRoom(
      id: room.id,
      owner: room.owner,
      name: room.name,
      subject: room.subject,
      audience: room.audience,
      allowInvitations: room.allowInvitations,
      members: [...room.members, ...userIds],
      avatarUrl: room.avatarUrl,
      custom: room.custom,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> remove(String roomId, String userId) async =>
      const Success(null);

  @override
  Future<Result<void>> leave(String roomId) async =>
      const Success(null);

  @override
  Future<Result<void>> updateRole(
          String roomId, String userId, RoomRole role) async =>
      const Success(null);

  @override
  Future<Result<void>> ban(String roomId, String userId,
          {String? reason}) async =>
      const Success(null);

  @override
  Future<Result<void>> unban(String roomId, String userId) async =>
      const Success(null);

  @override
  Future<Result<void>> muteUser(String roomId, String userId) async =>
      const Success(null);

  @override
  Future<Result<void>> unmuteUser(String roomId, String userId) async =>
      const Success(null);
}

class MockMessagesApi implements ChatMessagesApi {
  final MockChatClient _client;
  MockMessagesApi(this._client);

  @override
  Future<Result<ChatMessage>> get(String roomId, String messageId) async {
    final messages = _client._messages[roomId] ?? [];
    final msg = messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return const Failure(NotFoundFailure());
    return Success(msg);
  }

  @override
  Future<Result<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
  }) async {
    final msg = ChatMessage(
      id: _client._nextMessageId(),
      from: _client.currentUserId,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      metadata: metadata,
    );
    _client._messages.putIfAbsent(roomId, () => []);
    _client._messages[roomId]!.insert(0, msg);
    if (messageType == MessageType.reaction && reaction != null) {
      _client.emitEvent(ChatEvent.reactionAdded(
        roomId: roomId,
        messageId: referencedMessageId ?? msg.id,
        userId: msg.from,
        reaction: reaction,
      ));
    } else {
      _client.emitEvent(ChatEvent.newMessage(message: msg, roomId: roomId));
    }
    return Success(msg);
  }

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> list(
    String roomId, {
    CursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    final messages = _client._messages[roomId] ?? [];
    return Success(PaginatedResponse(items: messages, hasMore: false));
  }

  @override
  Future<Result<void>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) async =>
      const Success(null);

  @override
  Future<Result<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final messages = _client._messages[roomId];
    if (messages == null) return const Failure(NotFoundFailure());
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return const Failure(NotFoundFailure());
    messages[idx] = messages[idx].copyWith(text: text, metadata: metadata);
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String roomId, String messageId) async {
    _client._messages[roomId]?.removeWhere((m) => m.id == messageId);
    return const Success(null);
  }

  @override
  Future<Result<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) async =>
      const Success(null);

  @override
  Future<Result<void>> markRoomAsRead(String roomId,
          {String? lastReadMessageId}) async =>
      const Success(null);

  @override
  Future<Result<PaginatedResponse<ReadReceipt>>> getRoomReceipts(
          String roomId) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async =>
      const Success(null);

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    CursorPaginationParams? pagination,
  }) async {
    final messages = _client._messages[roomId] ?? [];
    final thread = messages.where((m) => m.id == messageId).toList();
    return Success(PaginatedResponse(items: thread, hasMore: false));
  }

  @override
  Future<Result<List<AggregatedReaction>>> getReactions(
          String roomId, String messageId, {bool forceRefresh = false}) async =>
      const Success([]);

  @override
  Future<Result<void>> deleteReaction(
          String roomId, String messageId) async =>
      const Success(null);

  @override
  Future<Result<void>> pinMessage(String roomId, String messageId) async =>
      const Success(null);

  @override
  Future<Result<void>> unpinMessage(
          String roomId, String messageId) async =>
      const Success(null);

  @override
  Future<Result<PaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    PaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    PaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<void>> report(String roomId, String messageId,
          {required String reason}) async =>
      const Success(null);

  @override
  Future<Result<PaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    PaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) async =>
      Success(ScheduledMessage(
        id: 'mock-scheduled-1',
        userId: _client.currentUserId,
        roomId: roomId,
        sendAt: sendAt,
        createdAt: DateTime.now(),
        text: text,
        metadata: metadata,
      ));

  @override
  Future<Result<PaginatedResponse<ScheduledMessage>>> listScheduled(
          String roomId) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<void>> cancelScheduled(
          String roomId, String scheduledId) async =>
      const Success(null);

  @override
  Future<Result<void>> clearChat(String roomId) async => const Success(null);

  @override
  Future<DateTime?> getClearedAt(String roomId) async => null;
}

class MockContactsApi implements ChatContactsApi {
  final MockChatClient _client;
  MockContactsApi(this._client);

  @override
  Future<Result<void>> add(String contactUserId) async {
    _client._contacts.add(contactUserId);
    return const Success(null);
  }

  @override
  Future<Result<PaginatedResponse<ChatContact>>> list(
      {PaginationParams? pagination, CachePolicy? cachePolicy}) async {
    final contacts =
        _client._contacts.map((id) => ChatContact(userId: id)).toList();
    return Success(PaginatedResponse(items: contacts, hasMore: false));
  }

  @override
  Future<Result<void>> remove(String contactUserId) async {
    _client._contacts.remove(contactUserId);
    return const Success(null);
  }

  @override
  Future<Result<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final msg = ChatMessage(
      id: _client._nextMessageId(),
      from: _client.currentUserId,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
    );
    return Success(msg);
  }

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    CursorPaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getConversationMessages(
    String conversationId, {
    CursorPaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<ChatPresence>> getPresence(String contactUserId) async =>
      Success(ChatPresence(
        userId: contactUserId,
        status: PresenceStatus.available,
        online: true,
      ));

  @override
  Future<Result<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async =>
      const Success(null);

  @override
  Future<Result<void>> block(String userId) async => const Success(null);

  @override
  Future<Result<void>> unblock(String userId) async => const Success(null);

  @override
  Future<Result<PaginatedResponse<String>>> listBlocked(
          {PaginationParams? pagination}) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));
}

class MockPresenceApi implements ChatPresenceApi {
  final String _currentUserId;
  final List<ChatPresence> _injectedContacts = [];
  int _getAllCallCount = 0;
  MockPresenceApi(this._currentUserId);

  /// Test helper: append a contact that will be returned by [getAll].
  void injectContact(ChatPresence presence) {
    _injectedContacts.add(presence);
  }

  /// Test helper: number of times [getAll] has been invoked.
  int get getAllCallCount => _getAllCallCount;

  /// Test helper: reset the call counter.
  void resetCallCount() {
    _getAllCallCount = 0;
  }

  @override
  Future<Result<ChatPresence>> getOwn() async => Success(ChatPresence(
        userId: _currentUserId,
        status: PresenceStatus.available,
        online: true,
      ));

  @override
  Future<Result<BulkPresenceResponse>> getAll() async {
    _getAllCallCount++;
    return Success(BulkPresenceResponse(
      own: ChatPresence(
        userId: _currentUserId,
        status: PresenceStatus.available,
        online: true,
      ),
      contacts: List<ChatPresence>.from(_injectedContacts),
    ));
  }

  @override
  Future<Result<void>> update({
    required PresenceStatus status,
    String? statusText,
  }) async =>
      const Success(null);
}

class MockAttachmentsApi implements ChatAttachmentsApi {
  @override
  Future<Result<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async =>
      const Success(AttachmentUploadResult(
        attachmentId: 'mock-attachment-1',
        raw: {'attachmentId': 'mock-attachment-1'},
      ));

  @override
  Future<Result<Uint8List>> download(
    String attachmentId, {
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) async =>
      Success(Uint8List(0));

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    CursorPaginationParams? pagination,
  }) async =>
      const Success(PaginatedResponse(items: [], hasMore: false));

  @override
  Future<Result<void>> deleteInRoom(String roomId, String messageId) async =>
      const Success(null);
}
