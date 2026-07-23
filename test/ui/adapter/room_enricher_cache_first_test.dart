import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Wraps [ChatRoomsApi.getUserRooms] to count `networkOnly` calls and,
/// while [gate] is set, block on it before returning — lets tests freeze a
/// background revalidation mid-flight to observe state deterministically
/// instead of racing real async scheduling.
class _CountingRoomsApi implements ChatRoomsApi {
  _CountingRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;
  int networkOnlyCalls = 0;
  Completer<void>? gate;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy == CachePolicy.networkOnly) {
      networkOnlyCalls++;
      final g = gate;
      if (g != null) await g.future;
    }
    return _delegate.getUserRooms(
      type: type,
      pagination: pagination,
      cachePolicy: cachePolicy,
    );
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

class _CountingRoomsClient implements ChatClient {
  _CountingRoomsClient(this._delegate)
    : rooms = _CountingRoomsApi(_delegate.rooms);

  final ChatClient _delegate;
  @override
  final _CountingRoomsApi rooms;

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

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  group('background revalidation + in-flight guard', () {
    late MockChatClient mock;
    late _CountingRoomsClient counting;
    late ChatUiAdapter adapter;

    setUp(() async {
      mock = MockChatClient(currentUserId: 'me');
      counting = _CountingRoomsClient(mock);
      adapter = ChatUiAdapter(
        client: counting,
        currentUser: me,
        manageAppLifecycle: false,
        // This group's assertions are about the in-flight concurrency
        // guard (_revalidating), not the temporal debounce added on top of
        // it — zero it out so a re-fire right after the gate opens isn't
        // also suppressed by the debounce. The debounce itself is covered
        // separately below.
        roomRevalidateDebounce: Duration.zero,
      );
      adapter.start();
      mock.seedRoom(const ChatRoom(id: 'boot', name: 'Bootstrap'));
      await counting.connect();
      await Future<void>.delayed(Duration.zero);
      // Bootstrap load: initializedNotifier is false so this always takes
      // the blocking network path, regardless of the realtime state.
      await adapter.rooms.load();
      expect(adapter.initializedNotifier.value, isTrue);
    });

    tearDown(() async {
      await adapter.dispose();
      await mock.dispose();
    });

    test(
      'a cache-fresh load fires a background revalidation instead of a hard skip',
      () async {
        final before = counting.rooms.networkOnlyCalls;
        await adapter.rooms.load();
        // The foreground call returns fast (cache-fresh skip branch) but a
        // background network pass should still have been dispatched.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(counting.rooms.networkOnlyCalls, greaterThan(before));
      },
    );

    test('repeated loads while a revalidation is in flight do not fan out into '
        'concurrent network passes for the same type', () async {
      final gate = Completer<void>();
      counting.rooms.gate = gate;

      // First cache-fresh load: fires a background revalidation that
      // immediately blocks on the gate before completing its own fetch.
      await adapter.rooms.load();
      final afterFirst = counting.rooms.networkOnlyCalls;

      // Second (and third) cache-fresh loads race in while the first
      // background revalidation is still parked on the gate.
      await adapter.rooms.load();
      await adapter.rooms.load();
      final afterRepeats = counting.rooms.networkOnlyCalls;

      // The in-flight guard must have short-circuited the repeats: no
      // additional `networkOnly` calls were dispatched for `type: all`
      // while the first one was still pending.
      expect(afterRepeats, afterFirst);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Once the first revalidation finishes, a fresh load is free to
      // fire another one.
      final afterDrain = counting.rooms.networkOnlyCalls;
      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(counting.rooms.networkOnlyCalls, greaterThan(afterDrain));
    });
  });

  group('background revalidation temporal debounce', () {
    test(
      'a reopen inside the debounce window is skipped; one past the window '
      'fires a fresh revalidation',
      () async {
        final mock = MockChatClient(currentUserId: 'me');
        final counting = _CountingRoomsClient(mock);
        final adapter = ChatUiAdapter(
          client: counting,
          currentUser: me,
          manageAppLifecycle: false,
          roomRevalidateDebounce: const Duration(milliseconds: 150),
        );
        adapter.start();
        mock.seedRoom(const ChatRoom(id: 'boot', name: 'Bootstrap'));
        await counting.connect();
        await Future<void>.delayed(Duration.zero);
        // Bootstrap: blocking network path, unrelated to the debounce.
        await adapter.rooms.load();
        expect(adapter.initializedNotifier.value, isTrue);

        // First reopen: cache-fresh branch fires + completes a background
        // revalidation.
        await adapter.rooms.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final afterFirstReopen = counting.rooms.networkOnlyCalls;

        // Second reopen, well inside the debounce window — the temporal
        // gate (not the in-flight guard, which already cleared) must skip
        // dispatching a new network pass.
        await adapter.rooms.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(counting.rooms.networkOnlyCalls, afterFirstReopen);

        // Once the debounce window has elapsed, a reopen fires again.
        await Future<void>.delayed(const Duration(milliseconds: 160));
        await adapter.rooms.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          counting.rooms.networkOnlyCalls,
          greaterThan(afterFirstReopen),
        );

        await adapter.dispose();
        await mock.dispose();
      },
    );
  });

  group('DM dedupe determinism', () {
    Future<ChatUiAdapter> buildAdapterWithDuplicateDm(
      List<String> roomOrder,
    ) async {
      final client = MockChatClient(currentUserId: 'me');
      client.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
      for (final id in roomOrder) {
        client.seedRoom(ChatRoom(id: id, members: const ['me', 'bob']));
      }
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
      );
      adapter.start();
      await adapter.rooms.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return adapter;
    }

    test('the same pair of duplicate DM rooms resolves to the same winner '
        'regardless of which one is discovered first', () async {
      final adapterAB = await buildAdapterWithDuplicateDm(['room1', 'room2']);
      final adapterBA = await buildAdapterWithDuplicateDm(['room2', 'room1']);

      final idsAB = adapterAB.roomListController.allRooms
          .map((r) => r.id)
          .toSet();
      final idsBA = adapterBA.roomListController.allRooms
          .map((r) => r.id)
          .toSet();

      // Exactly one of the pair survives in both orderings, and it's the
      // SAME one — the tie-break must not depend on resolution order.
      expect(idsAB.intersection({'room1', 'room2'}), {'room1'});
      expect(idsBA.intersection({'room1', 'room2'}), {'room1'});

      await adapterAB.dispose();
      await adapterBA.dispose();
    });
  });

  group('DM dedupe cache-vs-authoritative eviction', () {
    test(
      'a cache pass suppresses the losing DM room from display but leaves '
      'the persistent cache untouched; only an authoritative pass evicts it',
      () async {
        final mock = MockChatClient(currentUserId: 'me');
        final counting = _CountingRoomsClient(mock);
        final cache = _RecordingCache();
        final adapter = ChatUiAdapter(
          client: counting,
          currentUser: me,
          cache: cache,
          manageAppLifecycle: false,
        );
        adapter.start();
        mock.seedRoom(const ChatRoom(id: 'boot', name: 'Bootstrap'));
        await counting.connect();
        await Future<void>.delayed(Duration.zero);
        await adapter.rooms.load();
        expect(adapter.initializedNotifier.value, isTrue);

        mock.seedUser(const ChatUser(id: 'bob', displayName: 'Bob'));
        mock.seedRoom(const ChatRoom(id: 'room1', members: ['me', 'bob']));
        mock.seedRoom(const ChatRoom(id: 'room2', members: ['me', 'bob']));

        final gate = Completer<void>();
        counting.rooms.gate = gate;

        await adapter.rooms.load();
        // The cache pass's fire-and-forget DM resolution needs a beat to
        // settle; the background revalidation is frozen on the gate before
        // it can touch anything.
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          cache.deleteRoomCalls,
          0,
          reason:
              'a non-authoritative (cache) pass must never evict the '
              'persistent cache for the losing DM room',
        );
        final visibleAfterCache = adapter.roomListController.allRooms
            .map((r) => r.id)
            .toSet();
        expect(
          visibleAfterCache.intersection({'room1', 'room2'}),
          hasLength(1),
          reason: 'the losing row must still be suppressed from display',
        );

        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          cache.deleteRoomCalls,
          greaterThan(0),
          reason:
              'the authoritative background revalidation must evict the '
              'losing DM room from the persistent cache',
        );

        await adapter.dispose();
        await mock.dispose();
      },
    );
  });
}
