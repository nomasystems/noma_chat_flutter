import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
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

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async =>
      cachePolicy == CachePolicy.cacheOnly ? cacheResult : networkResult;

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
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _ScriptedClient client;
  late RoomListController roomList;
  late RoomEnricher enricher;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _ScriptedClient(mock);
    roomList = RoomListController();
    final dmContacts = DmContactRegistry();
    enricher = RoomEnricher(
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
      cache: null,
      l10n: () => ChatUiLocalizations.en,
      initializedNotifier: ValueNotifier<bool>(false),
      connectionStateNotifier: ValueNotifier<ChatConnectionState>(
        ChatConnectionState.disconnected,
      ),
      isDisposed: () => false,
      isDmDetail: (detail) => detail.type == RoomType.oneToOne,
      findCachedUser: (_) => null,
      cacheUsers: (_) {},
      ensureUserCached: (_) async {},
      updateRoomLastMessage: (_, _) {},
      removeChatController: (_) {},
    );
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
