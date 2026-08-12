import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

class _MockCache extends Mock implements ChatLocalDatasource {}

/// The roster shape `MembersApi` caches: bare rows, no pagination, no
/// expansion.
ChatPaginatedResponse<RoomUser> roster(
  List<String> ids, {
  bool hasMore = false,
  int? totalCount,
}) => ChatPaginatedResponse(
  items: [for (final id in ids) RoomUser(userId: id)],
  hasMore: hasMore,
  totalCount: totalCount ?? ids.length,
);

void main() {
  late _MockRest rest;
  late _MockCache cache;
  late CacheManager cm;
  late MembersApi api;

  setUpAll(() {
    registerFallbackValue(roster(const []));
  });

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    cm = CacheManager(config: const CacheConfig());
    api = MembersApi(rest: rest, userId: 'me', cache: cache, cacheManager: cm);

    when(
      () =>
          rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
    ).thenAnswer(
      (_) async => (
        {
          'users': [
            {'userId': 'me', 'userRole': 'owner'},
            {'userId': 'bob', 'userRole': 'user'},
          ],
          'hasMore': false,
        },
        2,
      ),
    );
    when(
      () => rest.delete(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => rest.putVoid(any(), data: any(named: 'data')),
    ).thenAnswer((_) async {});
    when(() => rest.postVoid(any())).thenAnswer((_) async {});
    when(
      () => rest.postRaw(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => null);

    when(
      () => cache.getRoomMembers(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.saveRoomMembers(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteRoomMembers(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
  });

  int restListCalls() => verify(
    () => rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
  ).callCount;

  group('read path', () {
    test('an api built without a cache still does the GET', () async {
      final bare = MembersApi(rest: rest, userId: 'me');

      final result = await bare.list('r1');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.items.map((m) => m.userId), ['me', 'bob']);
      expect(restListCalls(), 1);
    });

    test('an api built without a cache answers cacheOnly with a miss and '
        'emits nothing', () async {
      final bare = MembersApi(rest: rest, userId: 'me');

      final result = await bare.list('r1', cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      verifyNever(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      );
    });

    test('with no policy named, a failed fetch is a failure — not the '
        'roster on disk', () async {
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'stale'])));
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenThrow(Exception('offline'));

      final result = await api.list('r1');

      expect(result.isFailure, isTrue);
    });

    test('cacheOnly with a stored roster answers from disk without a '
        'request', () async {
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'zoe'])));

      final result = await api.list('r1', cachePolicy: CachePolicy.cacheOnly);

      expect(result.dataOrThrow.items.map((m) => m.userId), ['me', 'zoe']);
      verifyNever(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      );
    });

    test(
      'cacheOnly with nothing stored is a miss, not an empty roster',
      () async {
        final result = await api.list('r1', cachePolicy: CachePolicy.cacheOnly);

        expect(result.isFailure, isTrue);
        verifyNever(
          () => rest.getWithTotalCount(
            any(),
            queryParams: any(named: 'queryParams'),
          ),
        );
      },
    );

    test('cacheOnly with an unreadable store is a miss too — and still '
        'emits nothing', () async {
      when(() => cache.getRoomMembers('r1')).thenAnswer(
        (_) async => const ChatFailureResult(UnexpectedFailure('disk error')),
      );

      final result = await api.list('r1', cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      verifyNever(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      );
    });

    test('the default policy writes what it fetched to disk', () async {
      await api.list('r1');

      final captured =
          verify(
                () => cache.saveRoomMembers('r1', captureAny()),
              ).captured.single
              as ChatPaginatedResponse<RoomUser>;
      expect(captured.items.map((m) => m.userId), ['me', 'bob']);
      expect(captured.totalCount, 2);
      expect(captured.hasMore, isFalse);
    });

    test('cacheFirst falls back to the stale roster when the network '
        'fails', () async {
      await api.list('r1', cachePolicy: CachePolicy.networkOnly);
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenThrow(Exception('offline'));
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'stale'])));
      cm.invalidate('members:r1');

      final result = await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(result.dataOrThrow.items.map((m) => m.userId), ['me', 'stale']);
    });
  });

  group('shapes that must bypass the cache entirely', () {
    test('a paginated list ignores a roster sitting on disk', () async {
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'zoe'])));

      final result = await api.list(
        'r1',
        pagination: const ChatPaginationParams(limit: 10, offset: 10),
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.dataOrThrow.items.map((m) => m.userId), ['me', 'bob']);
      expect(restListCalls(), 1);
    });

    test('an expanded list ignores the bare roster on disk — serving it '
        'would blank every name and avatar', () async {
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'zoe'])));

      final result = await api.list(
        'r1',
        expand: const [RoomMemberExpand.users],
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.dataOrThrow.items.map((m) => m.userId), ['me', 'bob']);
      expect(restListCalls(), 1);
    });

    test('an expanded list does not write into the bare roster key '
        'either', () async {
      await api.list('r1', expand: const [RoomMemberExpand.users]);

      verifyNever(() => cache.saveRoomMembers(any(), any()));
    });

    test('a paginated list does not write into the bare roster key', () async {
      await api.list('r1', pagination: const ChatPaginationParams(limit: 5));

      verifyNever(() => cache.saveRoomMembers(any(), any()));
    });
  });

  group('local mutations invalidate the roster', () {
    /// Warms the TTL entry and points the store at a roster, so a later
    /// `cacheFirst` read hits disk unless something invalidated the key.
    Future<void> warm() async {
      await api.list('r1', cachePolicy: CachePolicy.networkOnly);
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'bob'])));
    }

    Future<int> readsAfter(Future<void> Function() mutation) async {
      await warm();
      await mutation();
      await api.list('r1', cachePolicy: CachePolicy.cacheFirst);
      return restListCalls();
    }

    test('invite', () async {
      expect(await readsAfter(() => api.invite('r1', userIds: ['zoe'])), 2);
    });

    test('remove', () async {
      expect(await readsAfter(() => api.remove('r1', 'bob')), 2);
    });

    test('leave', () async {
      expect(await readsAfter(() => api.leave('r1')), 2);
    });

    test('updateRole', () async {
      expect(
        await readsAfter(() => api.updateRole('r1', 'bob', RoomRole.admin)),
        2,
      );
    });

    test('ban', () async {
      expect(await readsAfter(() => api.ban('r1', 'bob')), 2);
    });

    test('unban', () async {
      expect(await readsAfter(() => api.unban('r1', 'bob')), 2);
    });

    test('muteUser does NOT — the mute flag does not ride on RoomUser, so '
        'the cached rows are still exactly right', () async {
      expect(await readsAfter(() => api.muteUser('r1', 'bob')), 1);
    });

    test('unmuteUser does NOT either', () async {
      expect(await readsAfter(() => api.unmuteUser('r1', 'bob')), 1);
    });

    test('a FAILED remove leaves the roster alone', () async {
      await warm();
      when(
        () => rest.delete(
          any(),
          queryParams: any(named: 'queryParams'),
          headers: any(named: 'headers'),
        ),
      ).thenThrow(Exception('offline'));

      await api.remove('r1', 'bob');
      await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(restListCalls(), 1);
    });

    test('a mutation on another room does not touch this roster', () async {
      await warm();

      await api.remove('other', 'bob');
      await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(restListCalls(), 1);
    });
  });

  group('a membership change also ages the room DETAIL', () {
    /// Stands in for `RoomsApi.get`, the sole owner and reader of
    /// `roomDetail:$roomId`. Its `memberCount` is precisely what a join or
    /// a removal changes, and nothing else in this file would notice the
    /// second key going unrefreshed.
    Future<int> detailFetchesAfter(Future<void> Function() mutation) async {
      var fetches = 0;
      Future<void> readDetail(CachePolicy policy) async {
        await cm.resolve<String>(
          key: 'roomDetail:r1',
          ttl: const CacheConfig().ttlRooms,
          policy: policy,
          fromCache: () async => 'stored detail',
          fromNetwork: () async {
            fetches++;
            return const ChatSuccess('fresh detail');
          },
          saveToCache: (_) async {},
        );
      }

      await readDetail(CachePolicy.networkOnly);
      await mutation();
      await readDetail(CachePolicy.cacheFirst);
      return fetches;
    }

    test('invite', () async {
      expect(
        await detailFetchesAfter(() => api.invite('r1', userIds: ['zoe'])),
        2,
      );
    });

    test('remove', () async {
      expect(await detailFetchesAfter(() => api.remove('r1', 'bob')), 2);
    });

    test('leave', () async {
      expect(await detailFetchesAfter(() => api.leave('r1')), 2);
    });

    test(
      'updateRole does NOT — the row changed, the head count did not',
      () async {
        expect(
          await detailFetchesAfter(
            () => api.updateRole('r1', 'bob', RoomRole.admin),
          ),
          1,
        );
      },
    );

    test('ban does NOT either', () async {
      expect(await detailFetchesAfter(() => api.ban('r1', 'bob')), 1);
    });
  });

  group('invalidation reaches the stored row, not only its TTL entry', () {
    /// `cacheOnly` skips the TTL ledger by design and the `networkFirst`
    /// fallback reads disk exactly when the network just failed, so a
    /// roster whose row survived its invalidation is served for as long as
    /// the device stays offline — an expelled member still listed, with
    /// name and avatar.
    test('a removal drops the row, so a later cacheOnly read is a '
        'miss', () async {
      final stored = <String, ChatPaginatedResponse<RoomUser>>{
        'r1': roster(['me', 'bob']),
      };
      when(() => cache.getRoomMembers(any())).thenAnswer(
        (i) async => ChatSuccess(stored[i.positionalArguments[0] as String]),
      );
      when(() => cache.deleteRoomMembers(any())).thenAnswer((i) async {
        stored.remove(i.positionalArguments[0] as String);
        return const ChatSuccess(null);
      });

      expect(
        (await api.list('r1', cachePolicy: CachePolicy.cacheOnly)).isSuccess,
        isTrue,
      );

      await api.remove('r1', 'bob');
      await pumpEventQueue();

      final afterRemoval = await api.list(
        'r1',
        cachePolicy: CachePolicy.cacheOnly,
      );
      expect(afterRemoval.isFailure, isTrue);
    });

    /// The TTL entry drops synchronously, but the row behind it cannot:
    /// [MembersApi.invalidateRoster] is reached from `void` chokepoints
    /// and never gets to await the store. Without a barrier on the read
    /// side, "expel someone, then read the roster from disk" is a race the
    /// stale row can win — and it hands back the very member just
    /// expelled.
    test('a cacheOnly read fired right after an invalidation waits for the '
        'row to go instead of racing it', () async {
      final stored = <String, ChatPaginatedResponse<RoomUser>>{
        'r1': roster(['me', 'bob']),
      };
      when(() => cache.getRoomMembers(any())).thenAnswer(
        (i) async => ChatSuccess(stored[i.positionalArguments[0] as String]),
      );
      when(() => cache.deleteRoomMembers(any())).thenAnswer((i) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        stored.remove(i.positionalArguments[0] as String);
        return const ChatSuccess(null);
      });

      api.invalidateRoster('r1');
      final immediately = await api.list(
        'r1',
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(immediately.isFailure, isTrue);
    });

    test('a role change drops the row too — a demoted admin must not keep '
        'painting as one', () async {
      await api.updateRole('r1', 'bob', RoomRole.admin);

      verify(() => cache.deleteRoomMembers('r1')).called(1);
    });

    test('the explicit adapter entry point drops it as well', () async {
      api.invalidateRoster('r1');

      verify(() => cache.deleteRoomMembers('r1')).called(1);
    });

    test('a mutation on another room leaves this row alone', () async {
      await api.remove('other', 'bob');

      verifyNever(() => cache.deleteRoomMembers('r1'));
    });
  });

  test(
    'invalidateRoster drops the key the adapter cannot name itself',
    () async {
      await api.list('r1', cachePolicy: CachePolicy.networkOnly);
      when(
        () => cache.getRoomMembers('r1'),
      ).thenAnswer((_) async => ChatSuccess(roster(['me', 'bob'])));

      api.invalidateRoster('r1');
      await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(restListCalls(), 2);
    },
  );
}
