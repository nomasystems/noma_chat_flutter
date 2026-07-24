import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Wraps [ChatRoomsApi] to replace the RESULT of the next `networkOnly`
/// [getUserRooms] call with either a scripted [UserRooms] page (a
/// successful-but-honest response — with an honest backend this is always
/// the caller's complete room set, full or empty) or a scripted failure
/// (simulating a 5xx / timeout), without touching what the mock actually
/// has seeded. Every other member delegates to the real [MockRoomsApi].
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  /// Consumed exactly once by the next `networkOnly` call, then reset to
  /// `null` so subsequent calls fall back to the real delegate.
  UserRooms? nextNetworkResult;

  /// Consumed exactly once by the next `networkOnly` call (checked before
  /// [nextNetworkResult]), simulating a failed network read — a 5xx,
  /// timeout, or connectivity drop — that must leave the room list intact
  /// no matter which caller (resync, pull-to-refresh, background
  /// revalidation) triggered it.
  ChatFailure? nextNetworkFailure;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy == CachePolicy.networkOnly && nextNetworkFailure != null) {
      final failure = nextNetworkFailure!;
      nextNetworkFailure = null;
      return ChatFailureResult<UserRooms>(failure);
    }
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
  _ScriptedRoomsClient(this._delegate)
    : rooms = _ScriptedRoomsApi(_delegate.rooms);

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
      roomRevalidateDebounce: Duration.zero,
    );
    adapter.start();
    mock.seedRoom(const ChatRoom(id: 'r1', name: 'Room One'));
    mock.seedRoom(const ChatRoom(id: 'r2', name: 'Room Two'));
    await scripted.connect();
    await Future<void>.delayed(Duration.zero);
    // Bootstrap: initializedNotifier is false so this always takes the
    // blocking network path regardless of the realtime state, populating
    // both rooms.
    await adapter.rooms.load();
    expect(adapter.initializedNotifier.value, isTrue);
    expect(
      adapter.connectionStateNotifier.value,
      ChatConnectionState.connected,
    );
    expect(adapter.roomListController.allRooms.map((r) => r.id).toSet(), {
      'r1',
      'r2',
    });
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  test(
    'a background revalidation whose network response omits a room DOES '
    'prune it — a successful response is honest with this backend, so it '
    'converges cross-device removals instead of being second-guessed',
    () async {
      // Cache is warm, WS is "connected" — the next `rooms.load()` takes
      // the trust-the-cache fast path and fires an unawaited background
      // revalidation. Script that revalidation's `networkOnly` response to
      // come back with only `r1` — the backend's honest, complete
      // room set now that `r2` was removed on another device.
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      );

      await adapter.rooms.load();
      // Let the unawaited `_backgroundRevalidate` finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1'},
        reason:
            'a successful (200) background revalidation is authoritative — '
            'this is exactly what closes a cross-device ghost room without '
            'waiting for a pull-to-refresh or a realtime event that may '
            'never arrive',
      );
    },
  );

  test(
    'a background revalidation whose network response comes back entirely '
    'empty DOES clear the list — a legitimate zero-rooms snapshot (the '
    'last room was removed on another device) (regression test for N0)',
    () async {
      scripted.rooms.nextNetworkResult = const UserRooms(rooms: []);

      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.roomListController.allRooms, isEmpty);
    },
  );

  test('a background revalidation whose network read FAILS (5xx/timeout) '
      'leaves the list completely intact', () async {
    scripted.rooms.nextNetworkFailure = const ServerFailure(statusCode: 503);

    await adapter.rooms.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      adapter.roomListController.allRooms.map((r) => r.id).toSet(),
      {'r1', 'r2'},
      reason:
          'a failed network read must never touch the list, regardless '
          'of which caller triggered it',
    );
  });

  test('an explicit forceNetwork refresh (pull-to-refresh) whose response '
      'omits a room prunes it — stays authoritative', () async {
    scripted.rooms.nextNetworkResult = const UserRooms(
      rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
    );

    final result = await adapter.rooms.load(forceNetwork: true);

    expect(result.isSuccess, isTrue);
    expect(
      adapter.roomListController.allRooms.map((r) => r.id).toSet(),
      {'r1'},
      reason:
          'an explicit, user-initiated pull-to-refresh is a deliberate '
          'request for a fresh authoritative snapshot and must keep '
          'reconciling deletions',
    );
  });

  test('an explicit forceNetwork refresh (pull-to-refresh) whose network read '
      'FAILS leaves the list intact', () async {
    scripted.rooms.nextNetworkFailure = const ServerFailure(statusCode: 503);

    final result = await adapter.rooms.load(forceNetwork: true);

    expect(result.isFailure, isTrue);
    expect(adapter.roomListController.allRooms.map((r) => r.id).toSet(), {
      'r1',
      'r2',
    });
  });

  test(
    'resync() after a reconnect whose network response comes back short '
    'DOES prune the missing room — the ghost room left behind by a removal '
    'that happened on another device while this one was disconnected is '
    'closed as soon as the reconnect fires, without waiting for a '
    'pull-to-refresh (closes the N0 cross-device-ghost regression)',
    () async {
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      );

      await adapter.resync();

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1'},
        reason:
            'resync() now trusts a successful response the same way '
            'pull-to-refresh and the background revalidation do — a 200 is '
            'the truth, honest backend or bust',
      );
    },
  );

  test('resync() after a reconnect whose network response comes back entirely '
      'empty clears the list — the last room was removed on another device '
      'while this one was offline, and reconnecting converges to that truth '
      '(closes the N0 permanent-ghost regression)', () async {
    scripted.rooms.nextNetworkResult = const UserRooms(rooms: []);

    await adapter.resync();

    expect(adapter.roomListController.allRooms, isEmpty);
  });

  test('resync() after a reconnect whose network read FAILS (5xx/timeout) '
      'leaves the list completely intact', () async {
    scripted.rooms.nextNetworkFailure = const ServerFailure(statusCode: 503);

    await adapter.resync();

    expect(
      adapter.roomListController.allRooms.map((r) => r.id).toSet(),
      {'r1', 'r2'},
      reason:
          'a failed resync must never touch the list — the whole point '
          'of failing outright instead of answering 200-partial is that '
          'the client can trust every success and ignore every failure',
    );
  });

  test('a truncated first page (hasMore: true) never prunes — the client '
      'knows this view is incomplete, so it upserts without dropping rows '
      'until either a full page arrives or a realtime event confirms the '
      'removal', () async {
    scripted.rooms.nextNetworkResult = const UserRooms(
      rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      hasMore: true,
    );

    await adapter.resync();

    expect(
      adapter.roomListController.allRooms.map((r) => r.id).toSet(),
      {'r1', 'r2'},
      reason:
          'hasMore:true means the backend truncated the page — pruning '
          'against it would drop every room past page 1',
    );
  });
}
