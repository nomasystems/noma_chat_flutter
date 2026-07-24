import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Overrides [ChatRoomsApi.get] to return a configurable [ChatResult]
/// (success or a specific typed failure) and counts how many times it was
/// called, so `ChatRoomsController.open` can be exercised without a real
/// network fetch.
class _StubRoomsApi implements ChatRoomsApi {
  _StubRoomsApi(this._delegate, this.result);
  final ChatRoomsApi _delegate;
  ChatResult<RoomDetail> result;
  int getCalls = 0;

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    getCalls++;
    return result;
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

class _StubRoomsClient implements ChatClient {
  _StubRoomsClient(this._delegate, ChatResult<RoomDetail> roomsGetResult)
    : rooms = _StubRoomsApi(_delegate.rooms, roomsGetResult);

  final ChatClient _delegate;
  @override
  final _StubRoomsApi rooms;

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

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  test(
    'a room already in the list is opened without a network fetch',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      mock.seedRoom(
        const ChatRoom(id: 'grp', name: 'Team', members: ['me', 'a']),
      );
      final client = _StubRoomsClient(
        mock,
        const ChatFailureResult(NotFoundFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      await adapter.rooms.load();
      // `load()` itself fetches per-room detail as part of its own bulk
      // enrichment — that's unrelated to `open()`. What matters is that
      // `open()` doesn't issue any ADDITIONAL `get()` call once the room is
      // already known to the list.
      final getCallsAfterLoad = client.rooms.getCalls;

      final result = await adapter.rooms.open('grp');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.roomId, 'grp');
      expect(client.rooms.getCalls, getCallsAfterLoad);
    },
  );

  test(
    'a room missing from the list is fetched from the server and added',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = _StubRoomsClient(
        mock,
        const ChatSuccess(
          RoomDetail(
            id: 'new-room',
            name: 'Fresh',
            type: RoomType.group,
            memberCount: 2,
            userRole: RoomRole.member,
            config: RoomConfig(allowInvitations: false),
          ),
        ),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('new-room');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.roomId, 'new-room');
      expect(client.rooms.getCalls, 1);
      expect(adapter.roomListController.getRoomById('new-room'), isNotNull);
      expect(adapter.roomListController.getRoomById('new-room')?.name, 'Fresh');
    },
  );

  test(
    'fetchIfMissing: false returns NotFoundFailure without hitting the network',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      final client = _StubRoomsClient(
        mock,
        const ChatFailureResult(NotFoundFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('missing', fetchIfMissing: false);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
      expect(client.rooms.getCalls, 0);
    },
  );

  test('a room the server reports gone maps to NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = _StubRoomsClient(
      mock,
      const ChatFailureResult(NotFoundFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('gone');

    expect(result.failureOrNull, isA<NotFoundFailure>());
  });

  test('an auth problem maps to AuthFailure, not NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = _StubRoomsClient(
      mock,
      const ChatFailureResult(AuthFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<AuthFailure>());
  });

  test(
    'a permission problem maps to ForbiddenFailure, not NotFoundFailure',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = _StubRoomsClient(
        mock,
        const ChatFailureResult(ForbiddenFailure(statusCode: 403)),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('some-room');

      expect(result.failureOrNull, isA<ForbiddenFailure>());
    },
  );

  test('the REST layer reporting a NetworkFailure (client otherwise connected) '
      'still propagates as NetworkFailure, not NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = _StubRoomsClient(
      mock,
      const ChatFailureResult(NetworkFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(client.rooms.getCalls, 1);
  });

  test('a client that already knows it is offline (disconnected) fast-fails '
      'without a network round-trip (R2-17)', () async {
    final mock = MockChatClient(currentUserId: 'me');
    // Deliberately NOT connected — MockChatClient defaults to
    // ChatConnectionState.disconnected, mirroring a cold app launch with
    // no network before the first `connect()` succeeds.
    final client = _StubRoomsClient(
      mock,
      const ChatSuccess(
        RoomDetail(
          id: 'some-room',
          name: 'Should never be reached',
          type: RoomType.group,
          memberCount: 2,
          userRole: RoomRole.member,
          config: RoomConfig(allowInvitations: false),
        ),
      ),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(
      client.rooms.getCalls,
      0,
      reason:
          'a known-offline client must fast-fail before ever '
          'attempting the network round-trip',
    );
  });

  test(
    'a network timeout maps to TimeoutFailure, not NotFoundFailure',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = _StubRoomsClient(
        mock,
        const ChatFailureResult(TimeoutFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('some-room');

      expect(result.failureOrNull, isA<TimeoutFailure>());
    },
  );
}
