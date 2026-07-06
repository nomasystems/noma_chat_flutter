import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
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

    when(
      () => cache.getRoomDetail(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.saveRoomDetail(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteRoom(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteRoomDetail(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteUnread(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.saveRooms(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getRooms(),
    ).thenAnswer((_) async => const ChatSuccess(<ChatRoom>[]));
    when(
      () => cache.saveUnreads(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getUnreads(),
    ).thenAnswer((_) async => const ChatSuccess(<UnreadRoom>[]));
    when(
      () => cache.saveInvitedRooms(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getInvitedRooms(),
    ).thenAnswer((_) async => const ChatSuccess(<InvitedRoom>[]));
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
      when(
        () => cache.getRoomDetail('r1'),
      ).thenAnswer((_) async => const ChatSuccess(cached));

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

    test(
      'patchPreferences() hits /preferences and invalidates room detail cache',
      () async {
        when(() => rest.patch(any(), data: any(named: 'data'))).thenAnswer(
          (_) async => {'muted': true, 'pinned': false, 'hidden': false},
        );

        final muted = await api.patchPreferences('r1', muted: true);
        final unmuted = await api.patchPreferences('r1', muted: false);

        expect(muted.isSuccess, true);
        expect(unmuted.isSuccess, true);
        verify(
          () => rest.patch('/rooms/r1/preferences', data: any(named: 'data')),
        ).called(2);
      },
    );

    test(
      'updateConfig() patches the cached UnreadRoom avatarUrl/name in '
      'place, so a room list rendered from cache before the invalidated '
      'TTL keys are refetched does not show the stale avatar',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});
        when(() => cache.getUnreads()).thenAnswer(
          (_) async => const ChatSuccess(<UnreadRoom>[
            UnreadRoom(
              roomId: 'r1',
              unreadMessages: 2,
              name: 'Old name',
              avatarUrl: 'https://old.example/avatar.png',
            ),
          ]),
        );

        final r = await api.updateConfig(
          'r1',
          name: 'New name',
          avatarUrl: 'https://new.example/avatar.png',
        );

        expect(r.isSuccess, true);
        final captured = verify(
          () => cache.saveUnreads(captureAny()),
        ).captured.single as List<UnreadRoom>;
        expect(captured, hasLength(1));
        expect(captured.single.roomId, 'r1');
        expect(captured.single.name, 'New name');
        expect(captured.single.avatarUrl, 'https://new.example/avatar.png');
        // Fields not touched by this updateConfig call are preserved.
        expect(captured.single.unreadMessages, 2);
      },
    );

    test(
      'updateConfig() with clearAvatar patches the cached avatarUrl to '
      'empty',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});
        when(() => cache.getUnreads()).thenAnswer(
          (_) async => const ChatSuccess(<UnreadRoom>[
            UnreadRoom(
              roomId: 'r1',
              unreadMessages: 0,
              avatarUrl: 'https://old.example/avatar.png',
            ),
          ]),
        );

        final r = await api.updateConfig('r1', clearAvatar: true);

        expect(r.isSuccess, true);
        final captured = verify(
          () => cache.saveUnreads(captureAny()),
        ).captured.single as List<UnreadRoom>;
        expect(captured.single.avatarUrl, '');
      },
    );

    test(
      'updateConfig() is a no-op on the unread cache when the room has no '
      'cached unread entry yet',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});
        when(
          () => cache.getUnreads(),
        ).thenAnswer((_) async => const ChatSuccess(<UnreadRoom>[]));

        final r = await api.updateConfig('unknown-room', name: 'New name');

        expect(r.isSuccess, true);
        verifyNever(() => cache.saveUnreads(any()));
      },
    );

    test(
      'updateConfig() with no name/avatarUrl/clearAvatar does not touch '
      'the unread cache',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        final r = await api.updateConfig('r1', subject: 'New subject');

        expect(r.isSuccess, true);
        verifyNever(() => cache.getUnreads());
        verifyNever(() => cache.saveUnreads(any()));
      },
    );

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
