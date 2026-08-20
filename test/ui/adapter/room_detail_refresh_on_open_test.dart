import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// Counts the room-detail reads and, while [gate] is set, holds each one
/// open *after* the answer has been computed — the shape of the real race:
/// the server prices the response before the next member joins, so a reply
/// that lands late still carries the old count.
class _CountingRoomsApi implements ChatRoomsApi {
  _CountingRoomsApi(this._delegate, this._log);

  final ChatRoomsApi _delegate;
  final List<String> _log;
  int detailReads = 0;
  Completer<void>? gate;

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    detailReads++;
    _log.add('get');
    final answer = await _delegate.get(roomId, cachePolicy: cachePolicy);
    final g = gate;
    if (g != null) await g.future;
    return answer;
  }

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
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds) =>
      _delegate.batchMarkAsRead(roomIds);

  @override
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      _delegate.batchGetUnread(roomIds);

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingClient implements ChatClient {
  _CountingClient(this._delegate, List<String> log)
    : rooms = _CountingRoomsApi(_delegate.rooms, log);

  final MockChatClient _delegate;

  @override
  final _CountingRoomsApi rooms;

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

/// A store whose detail eviction takes as long as a real one does, so the
/// order of "drop the stale copy" vs "read the fresh one" is observable
/// instead of collapsing into the same microtask.
class _SlowDetailCache extends MemoryChatLocalDatasource {
  _SlowDetailCache(this._log);

  final List<String> _log;

  @override
  Future<ChatResult<void>> deleteRoomDetail(String roomId) async {
    _log.add('delete:start');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _log.add('delete:end');
    return super.deleteRoomDetail(roomId);
  }
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const roomId = 'plan';

  late MockChatClient mock;
  late _CountingClient counting;
  late List<String> log;

  Future<ChatUiAdapter> boot({ChatLocalDatasource? cache}) async {
    final adapter = ChatUiAdapter(
      client: counting,
      currentUser: me,
      cache: cache,
      manageAppLifecycle: false,
    );
    adapter.start();
    mock.seedRoom(
      const ChatRoom(
        id: roomId,
        name: '[E2E] big room',
        members: ['me', 'ana', 'bruno'],
      ),
    );
    await counting.connect();
    await Future<void>.delayed(Duration.zero);
    await adapter.rooms.load();
    counting.rooms.detailReads = 0;
    log.clear();
    return adapter;
  }

  int? countOn(ChatUiAdapter adapter) =>
      adapter.roomListController.getRoomById(roomId)?.memberCount;

  setUp(() {
    log = [];
    mock = MockChatClient(currentUserId: 'me');
    counting = _CountingClient(mock, log);
  });

  tearDown(() async {
    await mock.dispose();
  });

  test('a join whose roster frame never arrived is picked up when the room '
      'is opened', () async {
    final adapter = await boot();
    addTearDown(adapter.dispose);
    expect(countOn(adapter), 3);

    // Sara joins the plan. The socket drops the frame: no UserJoinedEvent
    // ever reaches the router, which is the whole point — the count used
    // to stay wrong for the lifetime of the row, leaving and re-entering
    // the room included.
    mock.seedRoom(
      const ChatRoom(
        id: roomId,
        name: '[E2E] big room',
        members: ['me', 'ana', 'bruno', 'sara'],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      countOn(adapter),
      3,
      reason: 'nothing has told the client about the join yet',
    );

    adapter.setActiveRoom(roomId);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(countOn(adapter), 4);
  });

  test('opening a room the list does not know about does not fetch a '
      'detail for it', () async {
    final adapter = await boot();
    addTearDown(adapter.dispose);

    adapter.setActiveRoom('never-heard-of-it');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(counting.rooms.detailReads, 0);
  });

  test('a burst of roster frames costs one detail read plus one trailing '
      're-read, not one per frame', () async {
    final adapter = await boot();
    addTearDown(adapter.dispose);

    final gate = Completer<void>();
    counting.rooms.gate = gate;

    for (final userId in ['sara', 'pablo', 'marco', 'nuria', 'leo']) {
      mock.emitEvent(UserJoinedEvent(roomId: roomId, userId: userId));
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      counting.rooms.detailReads,
      1,
      reason: 'five frames must not become five GETs',
    );

    mock.seedRoom(
      const ChatRoom(
        id: roomId,
        name: '[E2E] big room',
        members: ['me', 'ana', 'bruno', 'sara', 'pablo', 'marco'],
      ),
    );
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      counting.rooms.detailReads,
      2,
      reason:
          'the frames that arrived while the read was in flight are worth '
          'exactly one re-read, and it has to happen: the in-flight answer '
          'was priced before they landed',
    );
    expect(countOn(adapter), 6);
  });

  test('the cached detail is dropped before the fresh read starts', () async {
    final cache = _SlowDetailCache(log);
    final adapter = await boot(cache: cache);
    addTearDown(adapter.dispose);

    mock.emitEvent(const UserJoinedEvent(roomId: roomId, userId: 'sara'));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      log.where((e) => e.startsWith('delete') || e == 'get').toList(),
      ['delete:start', 'delete:end', 'get'],
      reason:
          'an eviction still in flight when the response lands wipes the '
          'fresh detail instead of the stale one it was aimed at',
    );
  });
}
