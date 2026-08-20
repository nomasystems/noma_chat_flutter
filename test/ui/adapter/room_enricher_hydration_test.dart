import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// Answers `getUserRooms` from a script instead of from the real
/// cache-then-network machinery, so each hydration outcome can be produced
/// deterministically. Every other member is a plain delegation to the
/// mock client's own rooms API.
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  ChatResult<UserRooms> cacheResult = const ChatFailureResult(
    NetworkFailure('No cached data available'),
  );
  ChatResult<UserRooms> networkResult = const ChatFailureResult(
    NetworkFailure('offline'),
  );

  /// Parks the NEXT disk read until this completer is completed, then
  /// disarms itself, so a test can observe the enricher mid-hydration.
  Completer<void>? cacheGate;

  /// Twin of [cacheGate] for the network leg.
  Completer<void>? networkGate;

  /// Every `getUserRooms` in order: `'cache'` or `'network'`.
  final List<String> reads = [];
  int get cacheReads => reads.where((r) => r == 'cache').length;
  int get networkReads => reads.where((r) => r == 'network').length;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final isCache = cachePolicy == CachePolicy.cacheOnly;
    reads.add(isCache ? 'cache' : 'network');
    if (!isCache) {
      final netGate = networkGate;
      networkGate = null;
      if (netGate != null) await netGate.future;
      return networkResult;
    }
    final gate = cacheGate;
    cacheGate = null;
    if (gate != null) await gate.future;
    return cacheResult;
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

class _ScriptedClient implements ChatClient {
  _ScriptedClient(this._delegate) : rooms = _ScriptedRoomsApi(_delegate.rooms);

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

  @override
  int cancelOfflineSend(String tempId) => _delegate.cancelOfflineSend(tempId);
}

/// An in-memory store that starts with one room already flagged as
/// kicked and records every attempt to clear that flag.
class _RecordingKickedStore extends MemoryChatLocalDatasource {
  final List<String> unmarked = [];

  @override
  Future<ChatResult<Set<String>>> getKickedRoomIds() async =>
      const ChatSuccess({'k1'});

  @override
  Future<ChatResult<void>> unmarkKicked(String roomId) {
    unmarked.add(roomId);
    return super.unmarkKicked(roomId);
  }
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _ScriptedClient client;
  late RoomListController roomList;
  late RoomEnricher enricher;
  late ValueNotifier<bool> initialized;
  late List<int> roomsLoadedCalls;
  late bool adapterDisposed;
  late RoomEnricher Function({ChatLocalDatasource? cache}) buildEnricher;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _ScriptedClient(mock);
    roomList = RoomListController();
    initialized = ValueNotifier<bool>(false);
    roomsLoadedCalls = [];
    adapterDisposed = false;
    final dmContacts = DmContactRegistry();
    buildEnricher = ({ChatLocalDatasource? cache}) => RoomEnricher(
      client: client,
      controllers: ChatControllerRegistry(),
      roomList: roomList,
      dmContacts: dmContacts,
      userCache: UserCacheService(api: client.users, isDisposed: () => false),
      blockedUsers: BlockedUsersRegistry(),
      presence: PresenceRegistry(
        api: client.presence,
        roomList: roomList,
        dmContacts: dmContacts,
        isDisposed: () => false,
      ),
      currentUser: () => me,
      cache: cache,
      l10n: () => ChatUiLocalizations.en,
      initializedNotifier: initialized,
      connectionStateNotifier: ValueNotifier<ChatConnectionState>(
        ChatConnectionState.disconnected,
      ),
      onRoomsLoaded: (rooms) => roomsLoadedCalls.add(rooms.length),
      isDisposed: () => adapterDisposed,
      isDmDetail: (detail) => detail.type == RoomType.oneToOne,
      findCachedUser: (_) => null,
      cacheUsers: (_) {},
      ensureUserCached: (_) async {},
      updateRoomLastMessage: (_, _) {},
      removeChatController: (_) {},
    );
    enricher = buildEnricher();
  });

  tearDown(() async {
    enricher.dispose();
    roomList.dispose();
    await mock.dispose();
  });

  UserRooms roomsWith(List<String> ids) => UserRooms(
    rooms: [for (final id in ids) UnreadRoom(roomId: id, unreadMessages: 0)],
  );

  test('starts pending: nothing has been painted from disk yet', () {
    expect(
      enricher.hydrationNotifier.value.outcome,
      RoomHydrationOutcome.pending,
    );
    expect(enricher.hydrationNotifier.value.hasRun, isFalse);
    expect(enricher.hydrationNotifier.value.roomCount, 0);
  });

  test('a cache that could not be read reports unavailable, not empty — the '
      'host must keep showing its loading state', () async {
    client.rooms.cacheResult = const ChatFailureResult(
      UnexpectedFailure('cache unreadable'),
    );

    await enricher.loadAll();

    final status = enricher.hydrationNotifier.value;
    expect(status.outcome, RoomHydrationOutcome.unavailable);
    expect(status.hasRun, isTrue);
    expect(status.roomCount, 0);
  });

  test('a cache that answered with zero rooms reports empty, so the host can '
      'paint "no chats yet" instead of a spinner', () async {
    client.rooms.cacheResult = const ChatSuccess(UserRooms(rooms: []));

    await enricher.loadAll();

    final status = enricher.hydrationNotifier.value;
    expect(status.outcome, RoomHydrationOutcome.empty);
    expect(status.hasRun, isTrue);
    expect(status.roomCount, 0);
    expect(status.type, 'all');
  });

  test(
    'a cache with rooms reports hydrated and how many rows were painted',
    () async {
      mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
      mock.seedRoom(const ChatRoom(id: 'r2', name: 'Two'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1', 'r2']));

      await enricher.loadAll();

      final status = enricher.hydrationNotifier.value;
      expect(status.outcome, RoomHydrationOutcome.hydrated);
      expect(status.roomCount, 2);
    },
  );

  test(
    'the signal fires even when the cache phase paints exactly the rows '
    'already on screen — the room list itself notifies nothing there',
    () async {
      mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));
      await enricher.loadAll();

      var roomListNotifications = 0;
      void countRoomList() => roomListNotifications++;
      roomList.addListener(countRoomList);
      var hydrationNotifications = 0;
      void countHydration() => hydrationNotifications++;
      enricher.hydrationNotifier.addListener(countHydration);

      // Warm reopen: identical cache snapshot, so `mergeRooms` short-circuits
      // before `notifyListeners()`.
      await enricher.loadAll();

      roomList.removeListener(countRoomList);
      enricher.hydrationNotifier.removeListener(countHydration);

      expect(roomListNotifications, 0);
      // A listener attached after the fact still reads the outcome — that is
      // the point of publishing a value rather than an event.
      expect(
        enricher.hydrationNotifier.value.outcome,
        RoomHydrationOutcome.hydrated,
      );
      expect(enricher.hydrationNotifier.value.roomCount, 1);
      expect(hydrationNotifications, 0);
    },
  );

  group('hydrateFromCache — the disk phase on its own', () {
    test('paints from disk without claiming the list is authoritative: '
        'neither initializedNotifier nor onRoomsLoaded move', () async {
      mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));

      final status = await enricher.hydrateFromCache();

      expect(roomList.allRooms.map((r) => r.id), ['r1']);
      expect(status.outcome, RoomHydrationOutcome.hydrated);
      expect(client.rooms.networkReads, 0);
      expect(initialized.value, isFalse);
      expect(roomsLoadedCalls, isEmpty);
    });

    test('flips hasHydratedFromCache, and resetSession rearms it', () async {
      client.rooms.cacheResult = const ChatSuccess(UserRooms(rooms: []));
      expect(enricher.hasHydratedFromCache, isFalse);

      await enricher.hydrateFromCache();
      expect(enricher.hasHydratedFromCache, isTrue);

      enricher.resetSession();
      expect(enricher.hasHydratedFromCache, isFalse);
    });

    test('two concurrent calls share a single cache read', () async {
      mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));

      final results = await Future.wait([
        enricher.hydrateFromCache(),
        enricher.hydrateFromCache(),
      ]);

      expect(client.rooms.cacheReads, 1);
      expect(results.first.outcome, RoomHydrationOutcome.hydrated);
      expect(results.last.outcome, RoomHydrationOutcome.hydrated);
    });

    test('a resetSession landing mid-pass releases the single-flight slot, so '
        'the next session reads the disk itself', () async {
      mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      // Twin of "two concurrent calls share a single cache read" above,
      // with the reset as the only difference: sharing is exactly what must
      // NOT happen across a session boundary. Holding on to the outgoing
      // pass would hand the incoming session a result computed under the
      // previous epoch — which the epoch guard then refuses to count as its
      // hydration, leaving it with neither its own disk read nor
      // `hasHydratedFromCache`.
      final outgoing = enricher.hydrateFromCache();
      expect(client.rooms.cacheReads, 1);
      enricher.resetSession();
      final incoming = enricher.hydrateFromCache();

      expect(client.rooms.cacheReads, 2);
      disk.complete();
      await outgoing;
      await incoming;
      expect(enricher.hasHydratedFromCache, isTrue);
    });

    test('a disk pass that lands after the session ended paints nothing and '
        'publishes nothing', () async {
      mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['a1']));
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      final outgoing = enricher.hydrateFromCache();
      // What `signOut()` does: wipe the list and bump the epoch. It
      // deliberately does NOT dispose — the instance stays usable so the
      // next user can sign in on it — so `isDisposed` is not the guard
      // that can catch this.
      enricher.resetSession();
      roomList.setRooms(const []);

      disk.complete();
      await outgoing;

      expect(roomList.allRooms, isEmpty);
      expect(
        enricher.hydrationNotifier.value.outcome,
        RoomHydrationOutcome.pending,
      );
    });

    test("the previous identity's rooms are not merged into the next "
        "identity's list", () async {
      mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['a1']));
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      final outgoing = enricher.hydrateFromCache();
      enricher.resetSession();
      roomList.setRooms(const []);
      // User B signs in on the same instance and paints their own list.
      // The parked pass merges non-authoritatively, so anything it adds
      // here is never pruned again.
      roomList.setRooms(const [RoomListItem(id: 'b1')]);

      disk.complete();
      await outgoing;

      expect(roomList.allRooms.map((r) => r.id), ['b1']);
    });

    test('a resurrect that lands after the session ended does not clear the '
        "outgoing identity's deleted-room marker", () async {
      // Same defect the paint guard closes, one step earlier: these are
      // writes, and `signOut()` wipes the store right after bumping the
      // epoch. A pass still in flight would put the id back afterwards and
      // the next user would inherit it.
      final cutoff = DateTime.utc(2026);
      mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
      await mock.messages.setLocalClearedAt('a1', cutoff);
      await mock.rooms.markRoomDeleted('a1');
      client.rooms.cacheResult = ChatSuccess(
        UserRooms(
          rooms: [
            UnreadRoom(
              roomId: 'a1',
              unreadMessages: 1,
              lastMessageTime: cutoff.add(const Duration(minutes: 1)),
            ),
          ],
        ),
      );
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      final outgoing = enricher.hydrateFromCache();
      enricher.resetSession();

      disk.complete();
      await outgoing;
      await pumpEventQueue();

      expect((await mock.rooms.getDeletedRoomIds()).dataOrThrow, {'a1'});
    });

    test('a network pass that lands after the session ended does not clear '
        "the outgoing identity's kicked-room flags", () async {
      final store = _RecordingKickedStore();
      final withCache = buildEnricher(cache: store);
      addTearDown(withCache.dispose);
      mock.seedRoom(const ChatRoom(id: 'k1', name: 'Kicked room'));
      client.rooms.networkResult = ChatSuccess(roomsWith(['k1']));
      final network = Completer<void>();
      client.rooms.networkGate = network;

      final outgoing = withCache.loadAll();
      withCache.resetSession();

      network.complete();
      await outgoing;
      await pumpEventQueue();

      expect(store.unmarked, isEmpty);
    });

    test('a disk pass that lands after the adapter was disposed paints '
        'nothing either', () async {
      mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['a1']));
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      final outgoing = enricher.hydrateFromCache();
      // Disposal leaves the epoch alone — it is the OTHER half of the
      // staleness test, and the only half that catches a host that tore the
      // adapter down without signing out.
      adapterDisposed = true;

      disk.complete();
      await outgoing;

      expect(roomList.allRooms, isEmpty);
      expect(
        enricher.hydrationNotifier.value.outcome,
        RoomHydrationOutcome.pending,
      );
    });

    test('a pass that lands after the session ended does not count as the '
        "NEXT session's hydration", () async {
      mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
      client.rooms.cacheResult = ChatSuccess(roomsWith(['a1']));
      final disk = Completer<void>();
      client.rooms.cacheGate = disk;

      final outgoing = enricher.hydrateFromCache();
      enricher.resetSession();
      // The whole window `connect()` reads: the outgoing pass resolves
      // before the incoming session has asked for anything. Letting it set
      // the flag makes `connect()` skip `rooms.hydrate()` entirely, and the
      // incoming identity never paints from disk at all — a blank list
      // behind the handshake with a full store sitting right there.
      disk.complete();
      await outgoing;

      expect(enricher.hasHydratedFromCache, isFalse);
    });

    test('sequential calls are NOT deduped — the single-flight slot only '
        'collapses overlap', () async {
      client.rooms.cacheResult = const ChatSuccess(UserRooms(rooms: []));

      await enricher.hydrateFromCache();
      await enricher.hydrateFromCache();

      expect(client.rooms.cacheReads, 2);
    });
  });

  test('a network pass whose session ended neither marks the list '
      'initialized nor hands it to the host', () async {
    mock.seedRoom(const ChatRoom(id: 'a1', name: 'A room'));
    client.rooms.networkResult = ChatSuccess(roomsWith(['a1']));
    final wire = Completer<void>();
    client.rooms.networkGate = wire;

    final outgoing = enricher.loadAll();
    await pumpEventQueue();
    enricher.resetSession();
    roomList.setRooms(const []);

    wire.complete();
    await outgoing;

    // `initializedNotifier` is what makes the next `loadAll` trust the
    // cache and skip the network, and `onRoomsLoaded` is the host's "here
    // is your list" callback. Both fired by the outgoing identity's pass
    // would tell the incoming one that a list it never fetched is
    // authoritative.
    expect(initialized.value, isFalse);
    expect(roomsLoadedCalls, isEmpty);
    expect(roomList.allRooms, isEmpty);
  });

  test('loadAll still reads the cache first and the network second', () async {
    mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
    client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));
    client.rooms.networkResult = ChatSuccess(roomsWith(['r1']));

    await enricher.loadAll();

    expect(client.rooms.reads, ['cache', 'network']);
    expect(initialized.value, isTrue);
    expect(roomsLoadedCalls, isNotEmpty);
  });

  group('network failure masking', () {
    test('a cache that answered "you have zero rooms" does NOT mask a failed '
        'network pass', () async {
      client.rooms.cacheResult = const ChatSuccess(UserRooms(rooms: []));
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );

      final result = await enricher.loadAll();

      expect(result.isFailure, isTrue);
    });

    test(
      'a cache that had rooms to paint still masks a failed network pass',
      () async {
        mock.seedRoom(const ChatRoom(id: 'r1', name: 'One'));
        client.rooms.cacheResult = ChatSuccess(roomsWith(['r1']));
        client.rooms.networkResult = const ChatFailureResult(
          NetworkFailure('offline'),
        );

        final result = await enricher.loadAll();

        expect(result.isSuccess, isTrue);
      },
    );

    test('a cache whose every room the user deleted locally still masks the '
        'failed network pass — same empty outcome as the zero-rooms cache '
        'above, opposite verdict', () async {
      for (final id in ['r1', 'r2', 'r3']) {
        mock.seedRoom(ChatRoom(id: id, name: id.toUpperCase()));
        await client.rooms.markRoomDeleted(id);
      }
      client.rooms.cacheResult = ChatSuccess(roomsWith(['r1', 'r2', 'r3']));
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );

      final result = await enricher.loadAll();

      // The cache answered with three rooms, so it did have content; none
      // of it reached the list because the user deleted all three on this
      // device. The mask keys on what the cache RETURNED, not on what got
      // painted — reading the published outcome instead would turn a
      // legitimately empty list into a reported initialization failure and
      // the host would paint an error where "no chats yet" belongs.
      expect(result.isSuccess, isTrue);
      expect(roomList.allRooms, isEmpty);
      expect(
        enricher.hydrationNotifier.value.outcome,
        RoomHydrationOutcome.empty,
      );
    });

    test('a cache holding only an invitation counts as content and masks the '
        'failed network pass', () async {
      client.rooms.cacheResult = const ChatSuccess(
        UserRooms(
          rooms: [],
          invitedRooms: [InvitedRoom(roomId: 'r9', invitedBy: 'bob')],
        ),
      );
      client.rooms.networkResult = const ChatFailureResult(
        NetworkFailure('offline'),
      );

      final result = await enricher.loadAll();

      expect(result.isSuccess, isTrue);
    });
  });
}
