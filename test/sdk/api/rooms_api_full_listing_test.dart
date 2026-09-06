import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

/// A `GET /rooms` that behaves like the backend's: it paginates every
/// listing, applies [_defaultLimit] when the request carries no `limit`,
/// clamps a larger one to [_maxLimit], and reports `hasMore`.
class _PagingRestClient implements RestClient {
  _PagingRestClient({required this.roomCount, this.invitedCount = 0});

  static const int _defaultLimit = 50;
  static const int _maxLimit = 100;

  final int roomCount;
  final int invitedCount;

  /// Query maps of every `GET /rooms` this fake served, in order.
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    expect(path, '/rooms');
    requests.add({...?queryParams});

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
          {'roomId': 'room-$i', 'unreadMessages': 0, 'name': 'Room $i'},
      ],
      // Invitations ride along with every page, exactly as the backend
      // repeats them: the walk must not end up with duplicates.
      'invitedRooms': [
        for (var i = 0; i < invitedCount; i++)
          {'roomId': 'invite-$i', 'name': 'Invite $i'},
      ],
      'hasMore': end < roomCount,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RoomsApi.getUserRooms without pagination', () {
    test('walks every page so the listing is the whole room set', () async {
      final rest = _PagingRestClient(roomCount: 120);
      final api = RoomsApi(rest: rest);

      final result = await api.getUserRooms();

      expect(result.isSuccess, isTrue);
      final rooms = result.dataOrThrow.rooms;
      expect(rooms.length, 120);
      expect(rooms.first.roomId, 'room-0');
      expect(rooms.last.roomId, 'room-119');
      expect(
        rooms.map((r) => r.roomId).toSet().length,
        120,
        reason: 'no room is reported twice across pages',
      );
      expect(
        result.dataOrThrow.hasMore,
        isFalse,
        reason: 'the walk consumed the last page',
      );
      expect(
        rest.requests.length,
        2,
        reason: '120 rooms at the wire maximum of 100 is two requests',
      );
      expect(rest.requests.first['limit'], 100);
      expect(rest.requests.first['offset'], 0);
      expect(rest.requests[1]['offset'], 100);
    });

    test('a single short page costs a single request', () async {
      final rest = _PagingRestClient(roomCount: 7);
      final api = RoomsApi(rest: rest);

      final result = await api.getUserRooms();

      expect(result.dataOrThrow.rooms.length, 7);
      expect(rest.requests.length, 1);
    });

    test('invitations repeated on every page are kept once', () async {
      final rest = _PagingRestClient(roomCount: 120, invitedCount: 3);
      final api = RoomsApi(rest: rest);

      final result = await api.getUserRooms();

      expect(rest.requests.length, 2);
      expect(result.dataOrThrow.invitedRooms.length, 3);
      expect(
        result.dataOrThrow.invitedRooms.map((r) => r.roomId),
        ['invite-0', 'invite-1', 'invite-2'],
      );
    });

    test('an empty room set is one request and an empty answer', () async {
      final rest = _PagingRestClient(roomCount: 0);
      final api = RoomsApi(rest: rest);

      final result = await api.getUserRooms();

      expect(result.dataOrThrow.rooms, isEmpty);
      expect(rest.requests.length, 1);
    });
  });

  group('RoomsApi.getUserRooms with pagination', () {
    test('an explicit page is served as asked, and only that page', () async {
      final rest = _PagingRestClient(roomCount: 120);
      final api = RoomsApi(rest: rest);

      final result = await api.getUserRooms(
        pagination: const ChatPaginationParams(limit: 20, offset: 40),
      );

      expect(result.dataOrThrow.rooms.length, 20);
      expect(result.dataOrThrow.rooms.first.roomId, 'room-40');
      expect(
        result.dataOrThrow.hasMore,
        isTrue,
        reason: 'the caller drives its own paging from here',
      );
      expect(rest.requests.length, 1);
      expect(rest.requests.single['limit'], 20);
      expect(rest.requests.single['offset'], 40);
    });
  });
}
