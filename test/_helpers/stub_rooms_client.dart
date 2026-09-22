import 'dart:typed_data';

import 'package:noma_chat/noma_chat.dart';

/// What [ChatRoomsApi.get] answers for a disk-only read when nothing was
/// cached — the same failure the cache manager produces on a `cacheOnly`
/// miss.
const roomDetailCacheMiss = ChatFailureResult<RoomDetail>(
  NetworkFailure('No cached data available'),
);

/// Overrides [ChatRoomsApi.get] with one configurable answer for the
/// disk-only read ([CachePolicy.cacheOnly]) and another for the network
/// read, counting the two apart so `ChatRoomsController.open` can be
/// exercised without a real fetch and checked for "served from disk, no
/// round-trip".
class StubRoomsApi implements ChatRoomsApi {
  StubRoomsApi(
    this._delegate, {
    required this.networkResult,
    this.cachedResult = roomDetailCacheMiss,
  });

  final ChatRoomsApi _delegate;
  ChatResult<RoomDetail> networkResult;
  ChatResult<RoomDetail> cachedResult;
  int networkReads = 0;
  int cacheReads = 0;

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy == CachePolicy.cacheOnly) {
      cacheReads++;
      return cachedResult;
    }
    networkReads++;
    return networkResult;
  }

  // Everything else is a plain, real ChatRoomsApi (MockRoomsApi) — a
  // noSuchMethod-forwarding trick doesn't work here (that only works when
  // the delegate itself relies on noSuchMethod, e.g. a Mockito mock), so
  // every remaining member is delegated explicitly.
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
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) => _delegate.getUserRooms(
    type: type,
    pagination: pagination,
    cachePolicy: cachePolicy,
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<ChatResult<void>> delete(String roomId) => _delegate.delete(roomId);

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
    bool? lastMessageIsSystem,
    String? lastMessageReactionEmoji,
    String? lastMessageReactionTargetText,
    MessageType? lastMessageReactionTargetType,
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
    lastMessageIsSystem: lastMessageIsSystem,
    lastMessageReactionEmoji: lastMessageReactionEmoji,
    lastMessageReactionTargetText: lastMessageReactionTargetText,
    lastMessageReactionTargetType: lastMessageReactionTargetType,
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

/// A [ChatClient] identical to the wrapped one except for [rooms], which
/// is a [StubRoomsApi] over the delegate's own.
class StubRoomsClient implements ChatClient {
  StubRoomsClient(
    this._delegate, {
    required ChatResult<RoomDetail> networkResult,
    ChatResult<RoomDetail> cachedResult = roomDetailCacheMiss,
  }) : rooms = StubRoomsApi(
         _delegate.rooms,
         networkResult: networkResult,
         cachedResult: cachedResult,
       );

  final ChatClient _delegate;
  @override
  final StubRoomsApi rooms;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
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
  int get pendingOperationCount => _delegate.pendingOperationCount;
  @override
  Future<void> flushPendingOperations() => _delegate.flushPendingOperations();
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
    String? referencedMessageId,
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
    referencedMessageId: referencedMessageId,
  );

  @override
  int cancelOfflineSend(String tempId) => _delegate.cancelOfflineSend(tempId);
}
