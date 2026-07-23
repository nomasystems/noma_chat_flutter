import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Wraps [ChatRoomsApi] to replace the RESULT of the next `networkOnly`
/// [getUserRooms] call with a scripted [UserRooms] page, regardless of the
/// `type`/pagination the caller actually requested — letting each test drive
/// exactly what the "server" answered for a given `load()` call. Every other
/// member delegates to the real [MockRoomsApi].
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  /// Consumed exactly once by the next `networkOnly` call, then reset to
  /// `null` so subsequent calls fall back to the real delegate.
  UserRooms? nextNetworkResult;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy == CachePolicy.networkOnly && nextNetworkResult != null) {
      final scripted = nextNetworkResult!;
      nextNetworkResult = null;
      return ChatSuccess(scripted);
    }
    return _delegate.getUserRooms(
      type: type,
      pagination: pagination,
      cachePolicy: cachePolicy,
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
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) => _delegate.discover(query, pagination: pagination);

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) => _delegate.get(roomId, cachePolicy: cachePolicy);

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

class _ScriptedRoomsClient implements ChatClient {
  _ScriptedRoomsClient(this._delegate) : rooms = _ScriptedRoomsApi(_delegate.rooms);

  final ChatClient _delegate;
  @override
  final _ScriptedRoomsApi rooms;

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

/// BLOCKER-2 coverage: [RoomEnricher]'s authoritative `mergeRooms` prune must
/// only fire when the network response represents the caller's COMPLETE room
/// set — `type == 'all'` and no `hasMore` — mirroring the distinction
/// `RoomsApi.getUserRooms` already applies to its own cache writes. A
/// filtered view (`type: 'unread'`) or a truncated page (`hasMore: true`)
/// must never prune rows outside what it returned.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _ScriptedRoomsClient scripted;
  late ChatUiAdapter adapter;

  setUp(() async {
    mock = MockChatClient(currentUserId: 'me');
    scripted = _ScriptedRoomsClient(mock);
    adapter = ChatUiAdapter(
      client: scripted,
      currentUser: me,
      manageAppLifecycle: false,
    );
    adapter.start();
    mock.seedRoom(const ChatRoom(id: 'r1', name: 'Read Room'));
    mock.seedRoom(const ChatRoom(id: 'r2', name: 'Unread Room'));
    await scripted.connect();
    await Future<void>.delayed(Duration.zero);

    // Bootstrap the shared list with BOTH rooms via a scripted `type: 'all'`
    // network response — r1 read, r2 with a pending unread message.
    scripted.rooms.nextNetworkResult = const UserRooms(
      rooms: [
        UnreadRoom(roomId: 'r1', unreadMessages: 0),
        UnreadRoom(roomId: 'r2', unreadMessages: 3),
      ],
    );
    await adapter.rooms.load();
    expect(
      adapter.roomListController.allRooms.map((r) => r.id).toSet(),
      {'r1', 'r2'},
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  test(
    "load(type: 'unread') must NOT prune the read room from the shared list "
    '(BLOCKER-2)',
    () async {
      // The 'unread' filtered view only ever contains r2 — r1 has nothing
      // pending. A naive unconditional-authoritative merge would treat this
      // as the complete set and drop r1.
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r2', unreadMessages: 3)],
      );

      await adapter.rooms.load(type: 'unread', forceNetwork: true);

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1', 'r2'},
        reason:
            'a filtered (type: unread) response is not the complete room '
            'set, so it must only add/update rows — never prune the read '
            'room that legitimately falls outside the filter',
      );
    },
  );

  test(
    "load(type: 'all') with a genuinely honest response STILL prunes a room "
    'the backend no longer reports — no regression on the existing '
    'authoritative-prune behavior',
    () async {
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      );

      await adapter.rooms.load(forceNetwork: true);

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1'},
        reason:
            "a complete ('all', no hasMore) authoritative response must "
            'still prune rooms it no longer reports — the type-aware guard '
            'must not weaken the existing cross-device-removal behavior',
      );
    },
  );

  test(
    'a truncated first page (hasMore: true) must NOT prune rooms past page '
    '1 even when type is "all" (BLOCKER-2)',
    () async {
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
        hasMore: true,
      );

      await adapter.rooms.load(forceNetwork: true);

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1', 'r2'},
        reason:
            'a truncated page is demonstrably not the complete room set, so '
            'r2 (which simply landed on a later page) must survive',
      );
    },
  );
}
