import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The sign-up the adapter performs for a host that asked it to.
const _createUser = 'users.create';

/// The read that decides whether that sign-up happens at all.
const _getUser = 'users.get';

/// The room listing the host issues right after `connect()`. Recorded in the
/// same list so the fence can be stated as an order, not as two separate
/// counts.
const _loadRooms = 'rooms.load';

/// Counts every profile read and every sign-up, and can make either fail the
/// way a real one does: as a failed result, or as a throw.
class _ScriptedUsersApi implements ChatUsersApi {
  _ScriptedUsersApi(this._delegate, this._calls);

  final ChatUsersApi _delegate;
  final List<String> _calls;

  /// What the lookup answers. `null` lets the seeded mock answer.
  ChatResult<ChatUser>? getResult;

  /// What the sign-up answers. `null` lets the mock mint a user.
  ChatResult<ChatUser>? createResult;

  Object? throwOnGet;
  Object? throwOnCreate;

  int get getCalls => _calls.where((c) => c == _getUser).length;
  int get createCalls => _calls.where((c) => c == _createUser).length;

  @override
  Future<ChatResult<ChatUser>> get(
    String userId, {
    CachePolicy? cachePolicy,
  }) async {
    _calls.add(_getUser);
    final thrown = throwOnGet;
    if (thrown != null) throw thrown;
    return getResult ?? await _delegate.get(userId, cachePolicy: cachePolicy);
  }

  @override
  Future<ChatResult<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
  }) async {
    _calls.add(_createUser);
    lastCreateDisplayName = displayName;
    lastCreateAvatarUrl = avatarUrl;
    final thrown = throwOnCreate;
    if (thrown != null) throw thrown;
    return createResult ??
        await _delegate.create(
          externalIds: externalIds,
          passwords: passwords,
          displayName: displayName,
          avatarUrl: avatarUrl,
          bio: bio,
          email: email,
          custom: custom,
        );
  }

  String? lastCreateDisplayName;
  String? lastCreateAvatarUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the room listing and holds the handshake open, so a test can see
/// exactly how much of the bootstrap has run at each point of `connect()`.
class _ScriptedRoomsApi implements ChatRoomsApi {
  _ScriptedRoomsApi(this._delegate, this._calls);

  final ChatRoomsApi _delegate;
  final List<String> _calls;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    if (cachePolicy != CachePolicy.cacheOnly) _calls.add(_loadRooms);
    return _delegate.getUserRooms(
      type: type,
      pagination: pagination,
      cachePolicy: cachePolicy,
    );
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

class _ScriptedClient implements ChatClient {
  _ScriptedClient(this._delegate) {
    users = _ScriptedUsersApi(_delegate.users, calls);
    rooms = _ScriptedRoomsApi(_delegate.rooms, calls);
  }

  final MockChatClient _delegate;

  final List<String> calls = [];

  @override
  late final _ScriptedUsersApi users;

  @override
  late final _ScriptedRoomsApi rooms;

  /// Parks the handshake so a test can look at the call list while the
  /// socket is still coming up.
  Completer<void>? connectGate;

  @override
  Future<void> connect() async {
    final gate = connectGate;
    if (gate != null) await gate.future;
    return _delegate.connect();
  }

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
  late _ScriptedClient client;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _ScriptedClient(mock);
  });

  tearDown(() async {
    await mock.dispose();
  });

  /// The mock signs its own current user up at construction, so a test
  /// about an account chat has never seen has to say so out loud.
  void chatHasNoAccount() {
    client.users.getResult = const ChatFailureResult(NotFoundFailure());
  }

  ChatUiAdapter adapterWith({required bool bootstrap}) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
      bootstrapCurrentUser: bootstrap,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  group('the account bootstrap inside connect()', () {
    test(
      'reads the profile and leaves it alone when chat already has it',
      () async {
        mock.seedUser(me);
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();

        expect(client.users.getCalls, 1);
        expect(
          client.users.createCalls,
          0,
          reason: 'a profile that answers 200 is never signed up again',
        );
      },
    );

    test(
      'signs the account up exactly once when chat has never seen it',
      () async {
        chatHasNoAccount();
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();

        expect(client.users.getCalls, 1);
        expect(client.users.createCalls, 1);
      },
    );

    test('carries the name and photo the host handed the adapter', () async {
      chatHasNoAccount();
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(
          id: 'me',
          displayName: 'Me',
          avatarUrl: 'https://a/me',
        ),
        manageAppLifecycle: false,
        bootstrapCurrentUser: true,
      );
      addTearDown(adapter.dispose);

      await adapter.connect();

      expect(client.users.lastCreateDisplayName, 'Me');
      expect(client.users.lastCreateAvatarUrl, 'https://a/me');
    });

    test('never signs anyone up while the flag is off', () async {
      final adapter = adapterWith(bootstrap: false);

      await adapter.connect();

      expect(client.users.getCalls, 0);
      expect(client.users.createCalls, 0);
    });

    test(
      'a second connect on a live account does not sign it up again',
      () async {
        mock.seedUser(me);
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();
        await adapter.connect();

        expect(client.users.getCalls, 2);
        expect(client.users.createCalls, 0);
      },
    );
  });

  group('a bootstrap that cannot run', () {
    test(
      'does not sign an account up on the strength of a network error',
      () async {
        client.users.getResult = const ChatFailureResult(
          NetworkFailure('offline'),
        );
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();

        expect(client.users.getCalls, 1);
        expect(
          client.users.createCalls,
          0,
          reason: 'only a NotFound answer means the account is missing',
        );
      },
    );

    test(
      'logs the lookup it could not read instead of failing the connect',
      () async {
        final logs = <String>[];
        client.users.getResult = const ChatFailureResult(
          AuthFailure('token expired'),
        );
        final adapter = adapterWith(bootstrap: true)
          ..logger = (level, message) => logs.add('$level: $message');

        await adapter.connect();

        expect(
          logs.any((l) => l.startsWith('warn: profile bootstrap')),
          isTrue,
        );
      },
    );

    test('a failed sign-up does not abort the connection', () async {
      chatHasNoAccount();
      client.users.createResult = const ChatFailureResult(
        ServerFailure(statusCode: 500),
      );
      final adapter = adapterWith(bootstrap: true);

      await adapter.connect();

      expect(client.users.createCalls, 1);
    });

    test(
      'a sign-up that throws does not abort the connection either',
      () async {
        chatHasNoAccount();
        client.users.throwOnCreate = StateError('socket died mid-post');
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();

        expect(client.users.createCalls, 1);
      },
    );
  });

  group('the order WB fences', () {
    test(
      'the account is settled inside connect(), before the room load',
      () async {
        chatHasNoAccount();
        final adapter = adapterWith(bootstrap: true);

        await adapter.connect();
        await adapter.rooms.load();

        expect(client.calls, [_getUser, _createUser, _loadRooms]);
      },
    );

    test('nothing is read until the handshake is through', () async {
      chatHasNoAccount();
      final gate = Completer<void>();
      client.connectGate = gate;
      final adapter = adapterWith(bootstrap: true);

      final connecting = adapter.connect();
      await pumpEventQueue();

      expect(
        client.calls,
        isEmpty,
        reason: 'a profile read before the socket is up has no session',
      );

      gate.complete();
      await connecting;

      expect(client.calls, [_getUser, _createUser]);
    });
  });
}
