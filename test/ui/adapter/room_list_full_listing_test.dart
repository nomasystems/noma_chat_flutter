import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

/// A `GET /rooms` that paginates the way the backend does: a default
/// `limit` when the request omits one, a hard ceiling above it, and an
/// honest `hasMore`.
class _PagingRestClient implements RestClient {
  _PagingRestClient({required this.roomCount});

  static const int _defaultLimit = 50;
  static const int _maxLimit = 100;

  final int roomCount;
  int requestCount = 0;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    requestCount++;
    final limit = ((queryParams?['limit'] as int?) ?? _defaultLimit).clamp(
      1,
      _maxLimit,
    );
    final offset = (queryParams?['offset'] as int?) ?? 0;
    final start = offset.clamp(0, roomCount);
    final end = (start + limit).clamp(0, roomCount);
    return {
      'rooms': [
        for (var i = start; i < end; i++)
          {
            'roomId': 'room-${i.toString().padLeft(3, '0')}',
            'unreadMessages': 0,
            'name': 'Room $i',
          },
      ],
      'hasMore': end < roomCount,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Wires the real [RoomsApi] listing — the one that has to walk the pages —
/// on top of the mock client's room-detail surface, so the assertion below
/// is about what the room-list controller ends up holding rather than about
/// a fake that hands over everything in one go.
class _PagedRoomsApi implements ChatRoomsApi {
  _PagedRoomsApi(this._listing, this._delegate);

  final RoomsApi _listing;
  final ChatRoomsApi _delegate;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) => _listing.getUserRooms(type: type, pagination: pagination);

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async => const ChatFailureResult(NetworkFailure('no detail'));

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PagedClient implements ChatClient {
  _PagedClient(this._delegate, RestClient rest)
    : rooms = _PagedRoomsApi(RoomsApi(rest: rest), _delegate.rooms);

  final MockChatClient _delegate;

  @override
  final _PagedRoomsApi rooms;

  @override
  Future<void> connect() => _delegate.connect();
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
  late _PagingRestClient rest;
  late _PagedClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    rest = _PagingRestClient(roomCount: 120);
    client = _PagedClient(mock, rest);
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  test('an account past one backend page still lists every room', () async {
    await adapter.rooms.load(forceNetwork: true);

    final rooms = adapter.roomListController.rooms;
    expect(rooms.length, 120);
    expect(rooms.map((r) => r.id).toSet().length, 120);
    expect(adapter.roomListController.getRoomById('room-119'), isNotNull);
    expect(
      rest.requestCount,
      greaterThanOrEqualTo(2),
      reason: 'a 120-room account does not fit in one 100-room page, so the '
          'listing had to ask for the next one',
    );
  });
}
