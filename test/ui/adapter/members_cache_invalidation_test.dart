import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

/// The mock client with its members API swapped for the real cached one,
/// so the adapter's downcast finds something with a TTL ledger to drop.
class _ClientWithCachedMembers implements ChatClient {
  _ClientWithCachedMembers(this._delegate, this.members);

  final MockChatClient _delegate;

  @override
  final MembersApi members;

  @override
  ChatRoomsApi get rooms => _delegate.rooms;
  @override
  ChatUsersApi get users => _delegate.users;
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
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late CacheManager cm;
  late MembersApi members;
  late _ClientWithCachedMembers client;
  late ChatUiAdapter adapter;

  setUp(() async {
    mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(const ChatRoom(id: 'r1', name: 'R1', members: ['me', 'bob']));
    rest = _MockRest();
    store = MemoryChatLocalDatasource();
    cm = CacheManager(config: const CacheConfig());
    members = MembersApi(
      rest: rest,
      userId: 'me',
      cache: store,
      cacheManager: cm,
    );
    client = _ClientWithCachedMembers(mock, members);
    adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    adapter.start();
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'R1'),
    );

    when(
      () =>
          rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
    ).thenAnswer(
      (_) async => (
        {
          'users': [
            {'userId': 'me', 'userRole': 'owner'},
          ],
          'hasMore': false,
        },
        1,
      ),
    );

    // Warm the roster: one fetch, one write, one fresh TTL entry. Any
    // later `cacheFirst` read stays on disk unless something invalidated.
    await members.list('r1', cachePolicy: CachePolicy.networkOnly);
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  Future<void> drain() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  int fetches() => verify(
    () => rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
  ).callCount;

  Future<int> fetchesAfterCacheFirstRead() async {
    await members.list('r1', cachePolicy: CachePolicy.cacheFirst);
    return fetches();
  }

  test('with nothing happening the warm roster is served from disk', () async {
    expect(await fetchesAfterCacheFirstRead(), 1);
  });

  test('UserJoinedEvent invalidates the roster', () async {
    mock.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'zoe'));
    await drain();

    expect(await fetchesAfterCacheFirstRead(), 2);
  });

  test('UserLeftEvent invalidates the roster', () async {
    mock.emitEvent(const UserLeftEvent(roomId: 'r1', userId: 'bob'));
    await drain();

    expect(await fetchesAfterCacheFirstRead(), 2);
  });

  test('UserRoleChangedEvent invalidates the roster — the role rides on '
      'the cached row, so a promotion must not sit stale for a TTL', () async {
    mock.emitEvent(
      const UserRoleChangedEvent(
        roomId: 'r1',
        userId: 'bob',
        role: RoomRole.admin,
      ),
    );
    await drain();

    expect(await fetchesAfterCacheFirstRead(), 2);
  });

  test('an event about another room leaves this roster alone', () async {
    mock.emitEvent(const UserJoinedEvent(roomId: 'other', userId: 'zoe'));
    await drain();

    expect(await fetchesAfterCacheFirstRead(), 1);
  });
}
