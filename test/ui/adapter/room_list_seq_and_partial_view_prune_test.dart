import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Wraps [ChatRoomsApi.getUserRooms] to script the RESULT of the next
/// `networkOnly` call and, optionally, stall it on a [Completer] before
/// returning — lets a test freeze one fetch mid-flight while a second,
/// independent fetch races ahead and resolves first. Both [nextNetworkResult]
/// and [nextNetworkGate] are consumed exactly once, then reset to `null` so
/// later calls fall back to the real delegate (or the next scripted values).
class _ScriptedGatedRoomsApi implements ChatRoomsApi {
  _ScriptedGatedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  UserRooms? nextNetworkResult;
  Completer<void>? nextNetworkGate;

  /// Scripts the RESULT of the next `cacheOnly` call only — needed because
  /// [MockRoomsApi] ignores `cachePolicy` and always answers with every
  /// currently-seeded room, which would otherwise leak a just-seeded room
  /// into `loadAll`'s phase-1 (non-authoritative) pass and resolve its DM
  /// dedupe there instead of in the scripted authoritative network phase a
  /// test wants to exercise.
  UserRooms? nextCacheOnlyResult;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy == CachePolicy.networkOnly && nextNetworkResult != null) {
      final scripted = nextNetworkResult!;
      nextNetworkResult = null;
      final gate = nextNetworkGate;
      nextNetworkGate = null;
      if (gate != null) await gate.future;
      return ChatSuccess(scripted);
    }
    if (cachePolicy == CachePolicy.cacheOnly && nextCacheOnlyResult != null) {
      final scripted = nextCacheOnlyResult!;
      nextCacheOnlyResult = null;
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

class _ScriptedGatedRoomsClient implements ChatClient {
  _ScriptedGatedRoomsClient(this._delegate)
    : rooms = _ScriptedGatedRoomsApi(_delegate.rooms);

  final ChatClient _delegate;
  @override
  final _ScriptedGatedRoomsApi rooms;

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

class _RecordingCache extends MemoryChatLocalDatasource {
  int deleteRoomCalls = 0;
  int deleteRoomDetailCalls = 0;

  @override
  Future<ChatResult<void>> deleteRoom(String roomId) async {
    deleteRoomCalls++;
    return super.deleteRoom(roomId);
  }

  @override
  Future<ChatResult<void>> deleteRoomDetail(String roomId) async {
    deleteRoomDetailCalls++;
    return super.deleteRoomDetail(roomId);
  }
}

/// Fix-de-fondo coverage for the room-list's single pruning gate
/// (`RoomListController._acceptsPrune`, threaded via `nextSeq` /
/// `allowsInferredPrune`): a fetch may only prune when it represents the
/// caller's complete room set AND it isn't a stale, reordered result that
/// resolved after a fresher pass already landed.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  group('reordered fetch seq gate', () {
    late MockChatClient mock;
    late _ScriptedGatedRoomsClient scripted;
    late ChatUiAdapter adapter;

    setUp(() async {
      mock = MockChatClient(currentUserId: 'me');
      scripted = _ScriptedGatedRoomsClient(mock);
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
      // blocking network path, populating both rooms and flipping realtime
      // to "fresh" for the next call.
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

    test('a stale background revalidation that resolves AFTER a newer '
        'forceNetwork fetch already confirmed the room must not re-prune it '
        '(fix-de-fondo: monotonic seq gate)', () async {
      // The next `rooms.load()` takes the trust-the-cache fast path and
      // fires an unawaited background revalidation. Script that
      // revalidation's response to omit r2 — as if the backend, at the
      // time THIS fetch was dispatched, no longer listed it — but stall
      // it on `staleGate` so it doesn't actually land yet.
      final staleGate = Completer<void>();
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      );
      scripted.rooms.nextNetworkGate = staleGate;

      await adapter.rooms.load();

      // A forceNetwork fetch starts AFTER the stale one was dispatched
      // and — unlike it — resolves immediately, confirming BOTH rooms are
      // still current. This is the fresher pass.
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [
          UnreadRoom(roomId: 'r1', unreadMessages: 0),
          UnreadRoom(roomId: 'r2', unreadMessages: 0),
        ],
      );
      final freshResult = await adapter.rooms.load(forceNetwork: true);
      expect(freshResult.isSuccess, isTrue);
      expect(adapter.roomListController.allRooms.map((r) => r.id).toSet(), {
        'r1',
        'r2',
      });

      // Only now does the stale (older) background revalidation resolve.
      staleGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        adapter.roomListController.allRooms.map((r) => r.id).toSet(),
        {'r1', 'r2'},
        reason:
            'the stale pass omitted r2, but it was dispatched before — and '
            'resolved after — a fresher fetch that already confirmed r2; '
            'an out-of-order result must never undo what a newer pass '
            'already established',
      );
    });

    test('a genuinely fresher full snapshot still prunes a room the backend no '
        'longer reports — the seq gate never blocks in-order authoritative '
        'pruning (no regression)', () async {
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'r1', unreadMessages: 0)],
      );

      final result = await adapter.rooms.load(forceNetwork: true);

      expect(result.isSuccess, isTrue);
      expect(adapter.roomListController.allRooms.map((r) => r.id).toSet(), {
        'r1',
      });
    });
  });

  group('DM dedupe under a partial/paginated view', () {
    test('a duplicate-DM eviction discovered while resolving a filtered/'
        'truncated page suppresses the loser from the visible list but does '
        'NOT evict it from the persistent cache — a later complete snapshot '
        'can still reconcile it (fix-de-fondo: representsCompleteSet gate '
        'applies to the DM dedupe path too)', () async {
      final mock = MockChatClient(currentUserId: 'me');
      final scripted = _ScriptedGatedRoomsClient(mock);
      final cache = _RecordingCache();
      final adapter = ChatUiAdapter(
        client: scripted,
        currentUser: me,
        cache: cache,
        manageAppLifecycle: false,
        // MockRoomsApi.get always returns RoomType.group. Drive DM
        // detection by member count instead so the dedupe path runs.
        isDmRoom: (detail) => detail.memberCount == 2,
      );
      adapter.start();
      mock.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
      mock.seedRoom(const ChatRoom(id: 'room-old', members: ['me', 'bob']));

      // Bootstrap with only `room-old` in play — a single DM room, no
      // duplicate yet, so the mapping binds deterministically.
      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(adapter.dm.getRoomId('bob'), 'room-old');

      // A second DM room for the same contact shows up (the usual
      // find-existing-DM-vs-background-resolution race). Surface it via a
      // TRUNCATED page (`hasMore: true`) — the client can tell this fetch
      // is not the caller's complete room set. The cache-only phase is
      // scripted to still see only `room-old` — `MockRoomsApi` otherwise
      // ignores `cachePolicy` and would leak `room-new-empty` into that
      // non-authoritative pass, resolving the dedupe there (already
      // always gated) instead of in the authoritative-but-partial network
      // phase this test targets.
      mock.seedRoom(
        const ChatRoom(id: 'room-new-empty', members: ['me', 'bob']),
      );
      scripted.rooms.nextCacheOnlyResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'room-old', unreadMessages: 0)],
      );
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [UnreadRoom(roomId: 'room-new-empty', unreadMessages: 1)],
        hasMore: true,
      );
      await adapter.rooms.load(forceNetwork: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        cache.deleteRoomCalls,
        0,
        reason:
            'a truncated page is not the complete room set — the dedupe '
            'loser must not be permanently evicted from the cache on its '
            'say-so alone',
      );
      expect(
        cache.deleteRoomDetailCalls,
        0,
        reason: 'same as above for the detail cache entry',
      );

      final dmRoomsAfterPartial = adapter.roomListController.allRooms
          .where((r) => r.otherUserId == 'bob')
          .map((r) => r.id)
          .toSet();
      expect(
        dmRoomsAfterPartial.length,
        1,
        reason:
            'the loser is still suppressed from the VISIBLE list — '
            'showing both rows would never be correct',
      );

      // A later, genuinely complete snapshot re-lists BOTH rooms (the
      // loser was never actually deleted server-side, and the client
      // never told the server to delete it either — it only hid it).
      scripted.rooms.nextNetworkResult = const UserRooms(
        rooms: [
          UnreadRoom(roomId: 'room-old', unreadMessages: 0),
          UnreadRoom(roomId: 'room-new-empty', unreadMessages: 1),
        ],
      );
      await adapter.rooms.load(forceNetwork: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        cache.deleteRoomCalls,
        greaterThan(0),
        reason:
            'once a complete, authoritative snapshot resolves the same '
            'duplicate, the eviction DOES persist — the row was never '
            'permanently lost, only deferred until a trustworthy pass',
      );
      final dmRoomsAfterComplete = adapter.roomListController.allRooms
          .where((r) => r.otherUserId == 'bob')
          .map((r) => r.id)
          .toSet();
      expect(dmRoomsAfterComplete.length, 1);

      await adapter.dispose();
      await mock.dispose();
    });
  });
}
