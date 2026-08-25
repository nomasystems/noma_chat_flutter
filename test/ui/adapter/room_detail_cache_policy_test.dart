import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/cache_config.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRestClient extends Mock implements RestClient {}

/// A client whose `rooms` is the real cache-backed [RoomsApi] over a
/// stubbed REST layer, with every other surface delegated to the mock.
/// The policy the enricher passes to `rooms.get` only has an observable
/// effect when a [CacheManager] is wired underneath it, which the plain
/// [MockChatClient] does not have.
class _CacheBackedClient implements ChatClient {
  _CacheBackedClient(this._delegate, this.rooms);

  final MockChatClient _delegate;

  @override
  final ChatRoomsApi rooms;

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
  ChatAuthApi get auth => _delegate.auth;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'paolo', displayName: 'Paolo');
  const roomId = 'aa9da451-2fbb-461d-8ef5-9bc04f8e4565';

  late _MockRestClient rest;
  late MemoryChatLocalDatasource store;
  late CacheManager cacheManager;
  late RoomsApi rooms;
  late MockChatClient mock;
  late _CacheBackedClient client;

  // The room as chat_engine reports it before Pablo joins: owner + two
  // assistants.
  late List<String> roomMembers;
  late int detailReads;

  // `GET /v1/rooms/{id}` — the body `chat_engine_rooms_core:project_room/4`
  // builds, field for field.
  Map<String, dynamic> roomDetailBody() => {
    'id': roomId,
    'name': '[E2E] sala grande',
    'subject': null,
    'type': 'group',
    'createdAt': '2026-08-18T09:12:44Z',
    'memberCount': roomMembers.length,
    'userRole': 'user',
    'avatarUrl': null,
    'custom': <String, dynamic>{'planId': 'plan-aa9da451'},
    'muted': false,
    'pinned': false,
    'selfMuted': false,
    'config': <String, dynamic>{'allowInvitations': true},
  };

  // `GET /v1/rooms?type=all` — `chat_api_cb_rooms_listing:conversation_data/2`
  // for a room with nothing unread.
  Map<String, dynamic> roomsListBody() => {
    'rooms': [
      {'roomId': roomId, 'unreadMessages': 0, 'lastUnreadMessage': null},
    ],
    'invitedRooms': <Map<String, dynamic>>[],
    'hasMore': false,
  };

  setUp(() {
    roomMembers = ['000003d550a1be42fu0', 'alba', 'paolo'];
    detailReads = 0;
    rest = _MockRestClient();
    store = MemoryChatLocalDatasource();
    // No datasource on the manager: the TTL bookkeeping this test needs is
    // in-memory, and wiring one would leave the persist debounce timer
    // pending across the widget test.
    cacheManager = CacheManager(
      config: const CacheConfig(
        ttlRooms: Duration(hours: 24),
        defaultReadPolicy: CachePolicy.cacheFirst,
      ),
    );
    rooms = RoomsApi(rest: rest, cache: store, cacheManager: cacheManager);
    mock = MockChatClient(currentUserId: 'paolo');
    client = _CacheBackedClient(mock, rooms);

    when(
      () => rest.get(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.first as String;
      if (path == '/rooms') return roomsListBody();
      if (path == '/rooms/$roomId') {
        detailReads++;
        return roomDetailBody();
      }
      throw StateError('unexpected GET $path');
    });
  });

  tearDown(() async {
    await cacheManager.dispose();
    await mock.dispose();
  });

  test('opening the room re-reads the detail from the network even while the '
      'cached copy is inside its TTL', () async {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    addTearDown(adapter.dispose);
    adapter.start();
    await client.connect();
    await Future<void>.delayed(Duration.zero);
    await adapter.rooms.load();

    expect(
      adapter.roomListController.getRoomById(roomId)?.memberCount,
      3,
      reason: 'the first listing priced the room at three participants',
    );
    final readsAfterListing = detailReads;
    expect(readsAfterListing, greaterThan(0));

    // Pablo joins the plan while this device is not listening: no
    // `user_joined` frame reaches the router, so nothing invalidates the
    // cached detail. The server now answers four.
    roomMembers = [...roomMembers, 'pablo'];

    adapter.setActiveRoom(roomId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      detailReads,
      greaterThan(readsAfterListing),
      reason:
          'opening the room has to reach the server; a read served from a '
          'still-valid cache entry can only repeat the old count',
    );
    expect(adapter.roomListController.getRoomById(roomId)?.memberCount, 4);
  });

  test('a resync with the room already open re-reads its detail, so a join '
      'missed while disconnected reaches the header without leaving the '
      'room', () async {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    addTearDown(adapter.dispose);
    adapter.start();
    await client.connect();
    await Future<void>.delayed(Duration.zero);
    await adapter.rooms.load();

    adapter.setActiveRoom(roomId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.roomListController.getRoomById(roomId)?.memberCount, 3);

    // Pablo joins while this device is backgrounded / its socket is down:
    // the `user_joined` frame is never delivered, so nothing evicts the
    // cached detail. Reconnecting resyncs the list and the transcript.
    roomMembers = [...roomMembers, 'pablo'];
    final readsBeforeResync = detailReads;

    await adapter.resync();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      detailReads,
      greaterThan(readsBeforeResync),
      reason:
          'the list pass resolves the detail through the cache, so the '
          'resync has to re-read the foregrounded room itself',
    );
    expect(
      adapter.roomListController.getRoomById(roomId)?.memberCount,
      4,
      reason:
          'setActiveRoom does not fire again for a room already active, so '
          'without this the header keeps the old count for as long as the '
          'user stays in the room',
    );
  });

  test('the refreshed detail replaces the cached one, so a later cache-first '
      'read no longer serves the old count', () async {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    addTearDown(adapter.dispose);
    adapter.start();
    await client.connect();
    await Future<void>.delayed(Duration.zero);
    await adapter.rooms.load();

    roomMembers = [...roomMembers, 'pablo'];
    adapter.setActiveRoom(roomId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final readsBefore = detailReads;
    final cached = await rooms.get(roomId);

    expect(detailReads, readsBefore, reason: 'this read is a cache hit');
    expect(cached.dataOrNull?.memberCount, 4);
  });

  testWidgets('the group info page reads the detail from the network', (
    tester,
  ) async {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    addTearDown(adapter.dispose);
    adapter.start();

    // Warm the detail cache the way any listing does, then let Pablo join
    // without a frame.
    await rooms.get(roomId);
    final readsAfterWarmup = detailReads;
    roomMembers = [...roomMembers, 'pablo'];

    await tester.pumpWidget(
      MaterialApp(
        home: GroupInfoPage(adapter: adapter, roomId: roomId),
      ),
    );
    await tester.pumpAndSettle();

    expect(detailReads, greaterThan(readsAfterWarmup));
    expect(
      find.text('${ChatTheme.defaults.l10n.groupMembers} (4)'),
      findsOneWidget,
    );
  });
}
