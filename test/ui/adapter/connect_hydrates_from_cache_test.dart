import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Scripts `getUserRooms` so the disk read and the wire read are told
/// apart by policy and counted, and lets a test park either of them.
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  ChatResult<UserRooms> cacheResult = const ChatSuccess(UserRooms(rooms: []));
  ChatResult<UserRooms> networkResult = const ChatFailureResult(
    NetworkFailure('offline'),
  );

  /// Makes the disk read blow up, standing in for a corrupt store.
  bool cacheThrows = false;

  /// Holds the disk read open so a caller can be observed mid-hydration.
  Duration cacheDelay = Duration.zero;

  /// Parks the NEXT disk read until this completer is completed, then
  /// disarms itself — so one session's read can stay outstanding while a
  /// later session issues its own.
  Completer<void>? cacheGate;

  /// Payloads for the upcoming disk reads, consumed in order; a read past
  /// the end falls back to [cacheResult]. Bound at CALL time, so a parked
  /// read still answers with the snapshot its own session asked for.
  final List<ChatResult<UserRooms>> cacheQueue = [];

  /// Fired the instant a wire read is issued, so a test can observe what
  /// the room list already holds at that exact point.
  void Function()? onNetworkRead;

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
      onNetworkRead?.call();
      return networkResult;
    }
    final payload = cacheQueue.isNotEmpty
        ? cacheQueue.removeAt(0)
        : cacheResult;
    final gate = cacheGate;
    cacheGate = null;
    if (gate != null) await gate.future;
    if (cacheDelay > Duration.zero) await Future<void>.delayed(cacheDelay);
    if (cacheThrows) throw StateError('cache store is corrupt');
    return payload;
  }

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) => _delegate.get(roomId, cachePolicy: cachePolicy);

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Gates `connect()` on a completer so a test can assert on what the
/// adapter has already painted while the handshake is still outstanding.
class _GatedClient implements ChatClient {
  _GatedClient(this._delegate) : rooms = _ScriptedRoomsApi(_delegate.rooms);

  final MockChatClient _delegate;

  @override
  final _ScriptedRoomsApi rooms;

  Completer<void>? connectGate;
  int connectCalls = 0;

  @override
  Future<void> connect() async {
    connectCalls++;
    final gate = connectGate;
    if (gate != null) await gate.future;
    return _delegate.connect();
  }

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
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _GatedClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _GatedClient(mock);
    adapter = ChatUiAdapter(client: client, currentUser: me);
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  UserRooms roomsWith(List<String> ids) => UserRooms(
    rooms: [for (final id in ids) UnreadRoom(roomId: id, unreadMessages: 0)],
  );

  void seed(List<String> ids) {
    for (final id in ids) {
      mock.seedRoom(ChatRoom(id: id, name: id.toUpperCase()));
    }
    client.rooms.cacheResult = ChatSuccess(roomsWith(ids));
  }

  test('the cached rooms are on screen BEFORE the handshake resolves', () async {
    seed(['r1', 'r2']);
    final gate = Completer<void>();
    client.connectGate = gate;

    final connecting = adapter.connect();
    await pumpEventQueue();

    expect(adapter.roomListController.allRooms.map((r) => r.id), [
      'r1',
      'r2',
    ]);
    expect(gate.isCompleted, isFalse);
    expect(client.connectCalls, 1);

    gate.complete();
    await connecting;
  });

  test('connect() reads disk only — it never fetches the room list', () async {
    seed(['r1']);

    await adapter.connect();

    expect(client.rooms.cacheReads, 1);
    expect(client.rooms.networkReads, 0);
  });

  test('an unreadable store is logged and skipped, never fatal to the '
      'connection', () async {
    client.rooms.cacheThrows = true;
    final warnings = <String>[];
    adapter.logger = (level, message) => warnings.add('$level:$message');

    await adapter.connect();

    expect(client.connectCalls, 1);
    expect(warnings.where((w) => w.contains('hydration failed')), isNotEmpty);
  });

  test('a reconnect after a completed network pass does not re-read '
      'the cache', () async {
    seed(['r1']);
    client.rooms.networkResult = ChatSuccess(roomsWith(['r1']));

    await adapter.connect();
    await adapter.rooms.load();
    expect(adapter.initializedNotifier.value, isTrue);
    final readsSoFar = client.rooms.cacheReads;

    await adapter.connect();

    expect(client.rooms.cacheReads, readsSoFar);
  });

  test('signOut rearms the hydration: the next connect() reads disk '
      'again', () async {
    seed(['r1']);

    await adapter.connect();
    final readsSoFar = client.rooms.cacheReads;

    await adapter.signOut();
    await adapter.connect();

    expect(client.rooms.cacheReads, readsSoFar + 1);
  });

  test('a load() fired while a hydrate() is in flight still runs its own '
      'network pass', () async {
    seed(['r1']);
    client.rooms.cacheDelay = const Duration(milliseconds: 40);
    client.rooms.networkResult = ChatSuccess(roomsWith(['r1']));

    final hydrating = adapter.rooms.hydrate();
    final loading = adapter.rooms.load();
    await hydrating;
    final result = await loading;

    expect(result.isSuccess, isTrue);
    expect(client.rooms.networkReads, 1);
    expect(adapter.initializedNotifier.value, isTrue);
  });

  test('a signOut landing mid-hydration does not let the outgoing pass '
      'count as the incoming session\'s disk read', () async {
    seed(['r1']);
    client.rooms.cacheDelay = const Duration(milliseconds: 40);

    final connecting = adapter.connect();
    await adapter.signOut();
    await connecting;
    final readsSoFar = client.rooms.cacheReads;

    await adapter.connect();

    expect(client.rooms.cacheReads, readsSoFar + 1);
  });

  test('a connect() issued while the outgoing disk read is STILL in flight '
      'hydrates from its own cache instead of inheriting that pass', () async {
    seed(['r1']);
    mock.seedRoom(const ChatRoom(id: 'r9', name: 'R9'));
    // The outgoing session's disk read is parked; the incoming one answers
    // straight away with its own snapshot.
    final diskA = Completer<void>();
    client.rooms.cacheGate = diskA;
    client.rooms.cacheQueue
      ..add(ChatSuccess(roomsWith(['r1'])))
      ..add(ChatSuccess(roomsWith(['r9'])));

    final connectingA = adapter.connect();
    await pumpEventQueue();
    expect(client.rooms.cacheReads, 1);
    expect(adapter.roomListController.allRooms, isEmpty);

    // Logout lands while that read is outstanding, and the next user signs
    // in immediately — the window the single-flight slot has to be cleared
    // in. Note `connectingA` is deliberately NOT awaited here: awaiting it
    // would let the slot clear on its own and the race would never happen.
    await adapter.signOut();

    final handshakeB = Completer<void>();
    client.connectGate = handshakeB;
    final connectingB = adapter.connect();
    await pumpEventQueue();

    // The incoming session read the disk itself and had its rows on screen
    // before its handshake — the guarantee this whole path exists for.
    // Inheriting the outgoing pass leaves it with nothing to paint and,
    // because that pass belongs to an older epoch, never even records the
    // disk read as this session's.
    expect(client.rooms.cacheReads, 2);
    expect(adapter.roomListController.allRooms.map((r) => r.id), ['r9']);
    expect(handshakeB.isCompleted, isFalse);

    diskA.complete();
    handshakeB.complete();
    await connectingB;
    await connectingA;
  });

  test('the wire read never overtakes the disk read: loadRooms only goes to '
      'the network once the cached rows are on screen', () async {
    seed(['r1']);
    client.rooms.networkResult = ChatSuccess(roomsWith(['r1']));
    final disk = Completer<void>();
    client.rooms.cacheGate = disk;
    var paintedWhenNetworkFired = -1;
    client.rooms.onNetworkRead = () =>
        paintedWhenNetworkFired = adapter.roomListController.allRooms.length;

    final hydrating = adapter.rooms.hydrate();
    final loading = adapter.rooms.load();
    await pumpEventQueue();

    // Disk still outstanding → the wire read has not even been issued.
    expect(client.rooms.networkReads, 0);

    disk.complete();
    await hydrating;
    await loading;

    expect(client.rooms.networkReads, 1);
    expect(paintedWhenNetworkFired, 1);
  });

  test('a host that hydrated first makes connect() skip its own pass', () async {
    seed(['r1']);

    final status = await adapter.rooms.hydrate();
    expect(status.outcome, RoomHydrationOutcome.hydrated);
    expect(client.rooms.cacheReads, 1);

    await adapter.connect();

    expect(client.rooms.cacheReads, 1);
  });
}
