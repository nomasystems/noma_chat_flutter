import 'dart:async';
import 'dart:typed_data';

import '../cache/cache_policy.dart';
import '../client/chat_client.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/attachment.dart';
import '../models/contact.dart';
import '../models/health_status.dart';
import '../models/invite_result.dart';
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
import '../models/starred_message.dart';
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

  // Demo/test seedable chat-list metadata the real backend derives but the
  // mock `ChatRoom` doesn't carry. Drive the room tile (badge / pin / mute).
  final Map<String, int> _unread = {};
  final Map<String, bool> _pinned = {};
  final Map<String, bool> _muted = {};

  // Per-user starred messages (messageId -> roomId), most-recent-first
  // insertion order. Seeds [MockMessagesApi.listStarred].
  final Map<String, String> _starred = {};
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

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshRoom(String roomId) async {}

  void emitEvent(ChatEvent event) => _eventController.add(event);

  /// Test helper: register a room directly in the mock store so subsequent
  /// `client.rooms.get(roomId)` calls return a proper `RoomDetail`.
  void seedRoom(ChatRoom room) {
    _rooms[room.id] = room;
    _messages.putIfAbsent(room.id, () => []);
  }

  /// Test/demo helper: seed chat-list metadata (unread badge, pinned,
  /// muted) that the real backend computes/stores but the mock `ChatRoom`
  /// model doesn't carry. Null args leave the current value untouched.
  void seedRoomMeta(String roomId, {int? unread, bool? pinned, bool? muted}) {
    if (unread != null) _unread[roomId] = unread;
    if (pinned != null) _pinned[roomId] = pinned;
    if (muted != null) _muted[roomId] = muted;
  }

  /// Test helper: register a user directly in the mock store so subsequent
  /// `client.users.get(userId)` calls return them. Pair with [seedRoom]
  /// when a test exercises the DM-draft hydration path.
  void seedUser(ChatUser user) {
    _users[user.id] = user;
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

  /// Resolves a WhatsApp-style preview for a starred reference by looking up
  /// the stored [ChatMessage] in the room: its text when present, else a
  /// plain media label. Keeps mock-backed widgetbook/tests showing a body
  /// instead of a blank row. Returns `null` when the message isn't stored.
  String? _starredPreview(String roomId, String messageId) {
    final msgs = _messages[roomId];
    if (msgs == null) return null;
    for (final m in msgs) {
      if (m.id != messageId) continue;
      if (m.isDeleted) return 'This message was deleted';
      final text = m.text;
      if (text != null && text.isNotEmpty) return text;
      switch (m.messageType) {
        case MessageType.audio:
          return '🎤 Voice message';
        case MessageType.location:
          return '📍 Location';
        case MessageType.attachment:
          return m.fileName != null && m.fileName!.isNotEmpty
              ? '📄 ${m.fileName}'
              : '📎 Attachment';
        case MessageType.forward:
          return 'Forwarded';
        case MessageType.reaction:
        case MessageType.reply:
        case MessageType.regular:
          return '📎 Attachment';
      }
    }
    return null;
  }

  @override
  Future<void> logout() async {
    await disconnect();
    _rooms.clear();
    _messages.clear();
    _contacts.clear();
    _users.clear();
    _unread.clear();
    _pinned.clear();
    _muted.clear();
  }

  @override
  Future<void> dispose() async {
    await _eventController.close();
    await _stateController.close();
  }

  // The mock client has no real HTTP requests in flight; cancellation is a no-op.
  @override
  void cancelPendingRequests([String reason = 'cancelled']) {}

  // The mock does not have an offline queue, so the setter is a no-op.
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) {}
}

class MockAuthApi implements ChatAuthApi {
  @override
  Future<ChatResult<HealthStatus>> healthCheck() async =>
      const ChatSuccess(HealthStatus(status: ServiceStatus.ok));
}

class MockUsersApi implements ChatUsersApi {
  final MockChatClient _client;
  MockUsersApi(this._client);

  @override
  Future<ChatResult<ChatUser>> get(
    String userId, {
    CachePolicy? cachePolicy,
  }) async {
    final user = _client._users[userId];
    if (user == null) return const ChatFailureResult(NotFoundFailure());
    return ChatSuccess(user);
  }

  @override
  Future<ChatResult<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
  }) async {
    final id = 'mock-user-${_client._users.length}';
    final user = ChatUser(
      id: id,
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
      email: email,
      custom: custom,
      active: true,
    );
    _client._users[id] = user;
    return ChatSuccess(user);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> search(
    String query, {
    ChatPaginationParams? pagination,
  }) async {
    final matches = _client._users.values
        .where(
          (u) =>
              u.displayName?.toLowerCase().contains(query.toLowerCase()) ??
              false,
        )
        .toList();
    return ChatSuccess(ChatPaginatedResponse(items: matches, hasMore: false));
  }

  @override
  Future<ChatResult<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    bool clearAvatar = false,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  }) async {
    final existing = _client._users[userId];
    if (existing == null) return const ChatFailureResult(NotFoundFailure());
    final updated = ChatUser(
      id: userId,
      displayName: displayName ?? existing.displayName,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? existing.avatarUrl),
      bio: bio ?? existing.bio,
      email: email ?? existing.email,
      custom: custom ?? existing.custom,
      active: active ?? existing.active,
      role: existing.role,
      configuration: existing.configuration,
    );
    _client._users[userId] = updated;
    return ChatSuccess(updated);
  }

  @override
  Future<ChatResult<void>> deleteCurrentUser() async {
    _client._users.remove(_client.currentUserId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> delete(String userId) async {
    // Mirror the backend's own-account-only rule: deleting another user's
    // id is forbidden with the cannot_delete_other_user token.
    if (userId != _client.currentUserId) {
      return const ChatFailureResult(
        ForbiddenFailure(
          message: 'Cannot delete another user',
          errorToken: ChatErrorTokens.cannotDeleteOtherUser,
        ),
      );
    }
    if (!_client._users.containsKey(userId)) {
      return const ChatFailureResult(NotFoundFailure());
    }
    _client._users.remove(userId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatUser>> searchManaged({
    required String externalId,
  }) async => const ChatFailureResult(NotFoundFailure());

  @override
  Future<ChatResult<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  }) async => const ChatSuccess([]);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManagedByParent(
    String parentId, {
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ManagedUserConfiguration>> getManagedConfig(
    String userId,
  ) async => const ChatSuccess(UserConfiguration());

  @override
  Future<ChatResult<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  }) async => const ChatSuccess(null);
}

class MockRoomsApi implements ChatRoomsApi {
  final MockChatClient _client;
  MockRoomsApi(this._client);

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
    return ChatSuccess(room);
  }

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final rooms = _client._rooms.values.map((r) {
      final msgs = _client._messages[r.id] ?? const <ChatMessage>[];
      final last = msgs.isEmpty
          ? null
          : msgs.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
      return UnreadRoom(
        roomId: r.id,
        // Seeded via `seedRoomMeta`; the real backend computes this.
        unreadMessages: _client._unread[r.id] ?? 0,
        name: r.name,
        avatarUrl: r.avatarUrl,
        // Type drives RoomListItem.isGroup. The mock used to
        // hard-code `'group'` for every room which left DMs
        // misclassified, breaking the SDK's DM-aware title default.
        //  - `custom.type == 'announcement'` → announcement.
        //  - 2 members → one-to-one DM.
        //  - otherwise → group.
        type: r.custom?['type'] == 'announcement'
            ? 'announcement'
            : (r.members.length == 2 ? 'one-to-one' : 'group'),
        memberCount: r.members.length,
        // Last-message preview + time so the tile shows the snippet and
        // timestamp (and the list sorts by recency) instead of a bare
        // title. Derived from the seeded messages (max timestamp).
        lastMessage: last?.text,
        lastMessageTime: last?.timestamp,
        lastMessageUserId: last?.from,
        lastMessageId: last?.id,
        lastMessageType: last?.messageType,
      );
    }).toList();
    return ChatSuccess(UserRooms(rooms: rooms));
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) async {
    final matches = _client._rooms.values
        .where(
          (r) => r.name?.toLowerCase().contains(query.toLowerCase()) ?? false,
        )
        .map((r) => DiscoveredRoom(id: r.id, name: r.name, subject: r.subject))
        .toList();
    return ChatSuccess(ChatPaginatedResponse(items: matches, hasMore: false));
  }

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const ChatFailureResult(NotFoundFailure());
    // Same room-type classification as `listAll` above — without this
    // `_isDmDetail` returns false (default to group) and the host's
    // `RoomTitleResolver` never gets `isDm: true` for one-to-one rooms.
    final type = room.custom?['type'] == 'announcement'
        ? RoomType.announcement
        : (room.members.length == 2 ? RoomType.oneToOne : RoomType.group);
    return ChatSuccess(
      RoomDetail(
        id: room.id,
        name: room.name,
        subject: room.subject,
        type: type,
        memberCount: room.members.length,
        userRole: RoomRole.owner,
        config: RoomConfig(allowInvitations: room.allowInvitations),
        avatarUrl: room.avatarUrl,
        custom: room.custom,
        muted: _client._muted[roomId] ?? false,
        pinned: _client._pinned[roomId] ?? false,
      ),
    );
  }

  @override
  Future<ChatResult<void>> delete(String roomId) async {
    if (!_client._rooms.containsKey(roomId)) {
      return const ChatFailureResult(NotFoundFailure());
    }
    _client._rooms.remove(roomId);
    _client._messages.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar = false,
    Map<String, dynamic>? custom,
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const ChatFailureResult(NotFoundFailure());
    _client._rooms[roomId] = ChatRoom(
      id: room.id,
      owner: room.owner,
      name: name ?? room.name,
      subject: subject ?? room.subject,
      audience: room.audience,
      allowInvitations: room.allowInvitations,
      members: room.members,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? room.avatarUrl),
      custom: custom ?? room.custom,
    );
    // Other mutations (mute/pin/hide/leave) also emit RoomUpdatedEvent —
    // without this, in mock mode, changing the group name/avatar/description
    // did not propagate to the chat list, AppBar, or _userCache. The change
    // was visible inside GroupInfoPage (which reloads via `_loadDetail`)
    // but disappeared on exit since the cached state was never updated.
    _client._eventController.add(RoomUpdatedEvent(roomId: roomId));
    return const ChatSuccess(null);
  }

  // Room mutations mirror the real client: every successful mutation
  // surfaces a `RoomUpdatedEvent` so adapter code that depends on the
  // event behaves identically against the mock. The six toggles delegate
  // to [patchPreferences], matching the real client's unified behavior.

  final Map<String, RoomPreferences> _prefs = {};

  @override
  Future<ChatResult<RoomPreferences>> patchPreferences(
    String roomId, {
    bool? muted,
    DateTime? muteUntil,
    bool? pinned,
    bool? hidden,
  }) async {
    final current = _prefs[roomId] ?? const RoomPreferences();
    final merged = current.copyWith(
      muted: muteUntil != null ? true : (muted ?? current.muted),
      muteUntil: muteUntil ?? (muted == false ? null : current.muteUntil),
      pinned: pinned ?? current.pinned,
      hidden: hidden ?? current.hidden,
    );
    _prefs[roomId] = merged;
    _client.emitEvent(ChatEvent.roomUpdated(roomId: roomId));
    return ChatSuccess(merged);
  }

  @override
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(
    List<String> roomIds,
  ) async => ChatSuccess(
    roomIds.map((id) => UnreadRoom(roomId: id, unreadMessages: 0)).toList(),
  );

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
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const ChatFailureResult(NotFoundFailure());
    final wantUsers = expand.contains(RoomMemberExpand.users);
    final users = room.members.map((id) {
      // Mirror the backend: embed displayName + avatarUrl only when the
      // `users` expansion was requested, drawing from the known profiles.
      final profile = wantUsers ? _client._users[id] : null;
      return RoomUser(
        userId: id,
        displayName: profile?.displayName,
        avatarUrl: profile?.avatarUrl,
      );
    }).toList();
    return ChatSuccess(ChatPaginatedResponse(items: users, hasMore: false));
  }

  @override
  Future<ChatResult<InviteResult>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    String? token,
  }) async {
    final room = _client._rooms[roomId];
    if (room == null) return const ChatFailureResult(NotFoundFailure());
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
    return ChatSuccess(
      InviteResult([
        for (final id in userIds) InviteUserResult(userId: id, success: true),
      ]),
    );
  }

  @override
  Future<ChatResult<InviteResult>> joinWithToken(
    String roomId, {
    required String token,
  }) => invite(
    roomId,
    userIds: [_client.currentUserId],
    mode: RoomUserMode.inviteAndJoin,
    token: token,
  );

  @override
  Future<ChatResult<void>> remove(String roomId, String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> leave(String roomId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> ban(
    String roomId,
    String userId, {
    String? reason,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unban(String roomId, String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> muteUser(String roomId, String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unmuteUser(String roomId, String userId) async =>
      const ChatSuccess(null);
}

class MockMessagesApi implements ChatMessagesApi {
  final MockChatClient _client;
  MockMessagesApi(this._client);

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) async {
    final messages = _client._messages[roomId] ?? [];
    final msg = messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return const ChatFailureResult(NotFoundFailure());
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) async {
    final msg = ChatMessage(
      id: _client._nextMessageId(),
      from: _client.currentUserId,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      clientMessageId: clientMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      metadata: metadata,
    );
    _client._messages.putIfAbsent(roomId, () => []);
    _client._messages[roomId]!.insert(0, msg);
    if (messageType == MessageType.reaction && reaction != null) {
      _client.emitEvent(
        ChatEvent.reactionAdded(
          roomId: roomId,
          messageId: referencedMessageId ?? msg.id,
          userId: msg.from,
          reaction: reaction,
        ),
      );
    } else {
      _client.emitEvent(ChatEvent.newMessage(message: msg, roomId: roomId));
    }
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    final messages = _client._messages[roomId] ?? [];
    return ChatSuccess(ChatPaginatedResponse(items: messages, hasMore: false));
  }

  @override
  Future<ChatResult<ChatMessage>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => send(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
  );

  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final messages = _client._messages[roomId];
    if (messages == null) return const ChatFailureResult(NotFoundFailure());
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return const ChatFailureResult(NotFoundFailure());
    messages[idx] = messages[idx].copyWith(text: text, metadata: metadata);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    _client._messages[roomId]?.removeWhere((m) => m.id == messageId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) async => const ChatSuccess(null);

  /// Records each `markRoomAsRead` invocation as a `(roomId,
  /// lastReadMessageId)` tuple so tests can assert how often the
  /// adapter flushed read receipts and against which high-water
  /// mark. Cleared via [resetMarkRoomAsReadCalls].
  final List<({String roomId, String? lastReadMessageId})> markRoomAsReadCalls =
      [];

  /// Clears the [markRoomAsReadCalls] history. Convenient at the
  /// start of a test stage that wants to isolate a specific flush.
  void resetMarkRoomAsReadCalls() => markRoomAsReadCalls.clear();

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    markRoomAsReadCalls.add((
      roomId: roomId,
      lastReadMessageId: lastReadMessageId,
    ));
    return const ChatSuccess(null);
  }

  /// Records each `markRoomAsDelivered` invocation as a `(roomId,
  /// lastDeliveredMessageId)` tuple so tests can assert how the adapter
  /// confirms delivery and with which cursor.
  final List<({String roomId, String lastDeliveredMessageId})>
  markRoomAsDeliveredCalls = [];

  /// Clears the [markRoomAsDeliveredCalls] history.
  void resetMarkRoomAsDeliveredCalls() => markRoomAsDeliveredCalls.clear();

  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) async {
    markRoomAsDeliveredCalls.add((
      roomId: roomId,
      lastDeliveredMessageId: lastDeliveredMessageId,
    ));
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    ChatCursorPaginationParams? pagination,
  }) async {
    final messages = _client._messages[roomId] ?? [];
    final thread = messages.where((m) => m.id == messageId).toList();
    return ChatSuccess(ChatPaginatedResponse(items: thread, hasMore: false));
  }

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    @Deprecated(
      'Use cachePolicy: CachePolicy.networkOnly instead. '
      'forceRefresh will be removed in 1.0.',
    )
    bool forceRefresh = false,
    CachePolicy? cachePolicy,
  }) async => const ChatSuccess([]);

  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) async {
    _client.emitEvent(
      ChatEvent.reactionAdded(
        roomId: roomId,
        messageId: messageId,
        userId: _client.currentUserId,
        reaction: emoji,
      ),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unpinMessage(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> starMessage(String roomId, String messageId) async {
    _client._starred[messageId] = roomId;
    _client.emitEvent(
      ChatEvent.messageUpdated(roomId: roomId, messageId: messageId),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> unstarMessage(
    String roomId,
    String messageId,
  ) async {
    _client._starred.remove(messageId);
    _client.emitEvent(
      ChatEvent.messageUpdated(roomId: roomId, messageId: messageId),
    );
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> listStarred({
    ChatPaginationParams? pagination,
  }) async {
    final entries = _client._starred.entries.toList().reversed;
    final items = [
      for (final e in entries)
        StarredMessage(
          userId: _client.currentUserId,
          messageId: e.key,
          roomId: e.value,
          starredAt: DateTime.now(),
          preview: _client._starredPreview(e.value, e.key),
        ),
    ];
    return ChatSuccess(
      ChatPaginatedResponse(
        items: items,
        hasMore: false,
        totalCount: items.length,
      ),
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    String? roomId,
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) async => ChatSuccess(
    ScheduledMessage(
      id: 'mock-scheduled-1',
      userId: _client.currentUserId,
      roomId: roomId,
      sendAt: sendAt,
      createdAt: DateTime.now(),
      text: text,
      metadata: metadata,
    ),
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  ) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> cancelScheduled(
    String roomId,
    String scheduledId,
  ) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> clearChat(String roomId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) async =>
      const ChatSuccess(null);
}

class MockContactsApi implements ChatContactsApi {
  final MockChatClient _client;
  MockContactsApi(this._client);

  @override
  Future<ChatResult<void>> add(String contactUserId) async {
    _client._contacts.add(contactUserId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatContact>>> list({
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final contacts = _client._contacts
        .map((id) => ChatContact(userId: id))
        .toList();
    return ChatSuccess(ChatPaginatedResponse(items: contacts, hasMore: false));
  }

  @override
  Future<ChatResult<void>> remove(String contactUserId) async {
    _client._contacts.remove(contactUserId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatMessage>> sendDirectMessage(
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
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>>
  getConversationMessages(
    String conversationId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ChatPresence>> getPresence(String contactUserId) async =>
      ChatSuccess(
        ChatPresence(
          userId: contactUserId,
          status: PresenceStatus.available,
          online: true,
        ),
      );

  @override
  Future<ChatResult<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> block(String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unblock(String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));
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
  Future<ChatResult<ChatPresence>> getOwn() async => ChatSuccess(
    ChatPresence(
      userId: _currentUserId,
      status: PresenceStatus.available,
      online: true,
    ),
  );

  @override
  Future<ChatResult<BulkPresenceResponse>> getAll() async {
    _getAllCallCount++;
    return ChatSuccess(
      BulkPresenceResponse(
        own: ChatPresence(
          userId: _currentUserId,
          status: PresenceStatus.available,
          online: true,
        ),
        contacts: List<ChatPresence>.from(_injectedContacts),
      ),
    );
  }

  @override
  Future<ChatResult<void>> update({
    required PresenceStatus status,
    String? statusText,
  }) async => const ChatSuccess(null);
}

class MockAttachmentsApi implements ChatAttachmentsApi {
  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async => const ChatSuccess(
    AttachmentUploadResult(
      attachmentId: 'mock-attachment-1',
      raw: {'attachmentId': 'mock-attachment-1'},
    ),
  );

  @override
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  }) async => ChatSuccess(
    AttachmentSignedUrl(
      url: 'https://mock.invalid/attachments/$attachmentId?sig=mock',
      raw: const {'url': 'mock'},
    ),
  );

  @override
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) async => ChatSuccess(Uint8List(0));

  @override
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async => ChatSuccess(Uint8List(0));

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> deleteInRoom(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
}
