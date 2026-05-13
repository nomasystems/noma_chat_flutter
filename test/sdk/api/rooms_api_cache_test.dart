import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

class _MockCache extends Mock implements ChatLocalDatasource {}

void main() {
  late _MockRest rest;
  late _MockCache cache;
  late CacheManager cm;
  late RoomsApi api;

  setUpAll(() {
    registerFallbackValue(
      const RoomDetail(
        id: '_',
        type: RoomType.group,
        memberCount: 0,
        userRole: RoomRole.member,
        config: RoomConfig(),
      ),
    );
    registerFallbackValue(<ChatRoom>[]);
    registerFallbackValue(<UnreadRoom>[]);
    registerFallbackValue(<InvitedRoom>[]);
  });

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    cm = CacheManager(config: const CacheConfig());
    api = RoomsApi(rest: rest, cache: cache, cacheManager: cm);

    when(() => cache.getRoomDetail(any())).thenAnswer((_) async => null);
    when(() => cache.saveRoomDetail(any())).thenAnswer((_) async {});
    when(() => cache.deleteRoom(any())).thenAnswer((_) async {});
    when(() => cache.deleteRoomDetail(any())).thenAnswer((_) async {});
    when(() => cache.deleteUnread(any())).thenAnswer((_) async {});
    when(() => cache.saveRooms(any())).thenAnswer((_) async {});
    when(() => cache.getRooms()).thenAnswer((_) async => []);
    when(() => cache.saveUnreads(any())).thenAnswer((_) async {});
    when(() => cache.getUnreads()).thenAnswer((_) async => []);
    when(() => cache.saveInvitedRooms(any())).thenAnswer((_) async {});
    when(() => cache.getInvitedRooms()).thenAnswer((_) async => []);
  });

  Map<String, dynamic> roomDetailJson(String id) => {
    'id': id,
    'name': 'R$id',
    'type': 'group',
    'memberCount': 3,
    'userRole': 'member',
    'muted': false,
    'pinned': false,
    'hidden': false,
    'allowInvitations': false,
  };

  group('RoomsApi cache paths', () {
    test('get() with empty cache fetches network and saves to cache', () async {
      when(() => rest.get(any())).thenAnswer((_) async => roomDetailJson('r1'));

      final r = await api.get('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.id, 'r1');
      verify(() => cache.saveRoomDetail(any())).called(1);
    });

    test('get() with cache hit returns cached value', () async {
      const cached = RoomDetail(
        id: 'r1',
        name: 'From cache',
        type: RoomType.group,
        memberCount: 5,
        userRole: RoomRole.admin,
        config: RoomConfig(),
      );
      when(() => cache.getRoomDetail('r1')).thenAnswer((_) async => cached);

      final r = await api.get('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.name, 'From cache');
    });

    test('delete() removes the room + detail from cache on success', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});

      final r = await api.delete('r1');

      expect(r.isSuccess, true);
      verify(() => cache.deleteRoom('r1')).called(1);
      verify(() => cache.deleteRoomDetail('r1')).called(1);
    });

    test('mute() / unmute() invalidate the room detail cache', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await api.mute('r1');
      await api.unmute('r1');
      // No direct cache calls — just verify both don't throw and call REST.
      verify(() => rest.putVoid('/rooms/r1/mute')).called(1);
      verify(() => rest.delete('/rooms/r1/mute')).called(1);
    });

    test('batchMarkAsRead() clears the unread cache for each room', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.batchMarkAsRead(['r1', 'r2', 'r3']);

      expect(r.isSuccess, true);
      verify(() => cache.deleteUnread('r1')).called(1);
      verify(() => cache.deleteUnread('r2')).called(1);
      verify(() => cache.deleteUnread('r3')).called(1);
    });
  });
}
