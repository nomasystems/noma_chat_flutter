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
  late CacheManager cacheManager;
  late CachedMessagesApi api;

  setUpAll(() {
    registerFallbackValue(
      ChatMessage(id: '_fallback', from: '_', timestamp: DateTime(2026)),
    );
    registerFallbackValue(const ReadReceipt(userId: '_'));
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(
      MessagePin(
        roomId: '_',
        messageId: '_',
        pinnedBy: '_',
        pinnedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(<ChatMessage>[]);
    registerFallbackValue(<ReadReceipt>[]);
    registerFallbackValue(<MessagePin>[]);
    registerFallbackValue(<AggregatedReaction>[]);
  });

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    cacheManager = CacheManager(config: const CacheConfig());
    api = CachedMessagesApi(
      rest: rest,
      cache: cache,
      cacheManager: cacheManager,
    );

    // Permissive defaults for cache calls.
    when(
      () => cache.getMessages(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => const ChatSuccess(<ChatMessage>[]));
    when(
      () => cache.saveMessages(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getClearedAt(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getReceipts(any()),
    ).thenAnswer((_) async => const ChatSuccess(<ReadReceipt>[]));
    when(
      () => cache.saveReceipts(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getReactions(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(<AggregatedReaction>[]));
    when(
      () => cache.saveReactions(any(), any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getPins(any()),
    ).thenAnswer((_) async => const ChatSuccess(<MessagePin>[]));
    when(
      () => cache.savePins(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deletePin(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.updateMessage(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteMessage(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteUnread(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.setClearedAt(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.clearMessages(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.clearPendingMessages(any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.getHiddenMessageIds(any()),
    ).thenAnswer((_) async => const ChatSuccess(<String>{}));
  });

  Map<String, dynamic> msgJson(String id) => {
    'id': id,
    'from': 'u1',
    'timestamp': '2026-01-01T00:00:00Z',
    'text': 't',
    'messageType': 'regular',
  };

  // Sync-mode send echo: the backend stamps the request's clientMessageId
  // into the persisted metadata, which is what marks the echo as
  // authoritative (non-provisional) and keeps the cache write-through on.
  Map<String, dynamic> syncEchoJson(String id) => {
    ...msgJson(id),
    'metadata': {'clientMessageId': 'cmid-$id'},
  };

  group('MessagesApi cache integration', () {
    test('list() with empty cache falls through to network', () async {
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer(
        (_) async => {
          'messages': [msgJson('m1')],
          'hasMore': false,
        },
      );

      final r = await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.id, 'm1');
    });

    test('list() with cache hit returns cached items', () async {
      when(
        () => cache.getMessages(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => ChatSuccess(<ChatMessage>[
          ChatMessage(
            id: 'c1',
            from: 'u1',
            timestamp: DateTime(2026, 1, 1),
            text: 'cached',
          ),
        ]),
      );

      final r = await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.id, 'c1');
    });

    test('list() respects clearedAt filtering', () async {
      when(
        () => cache.getClearedAt(any()),
      ).thenAnswer((_) async => ChatSuccess(DateTime(2026, 6, 1)));
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer(
        (_) async => {
          'messages': [
            {
              'id': 'old',
              'from': 'u1',
              'timestamp': '2026-01-01T00:00:00Z',
              'text': 'old',
              'messageType': 'regular',
            },
            {
              'id': 'new',
              'from': 'u1',
              'timestamp': '2026-12-01T00:00:00Z',
              'text': 'new',
              'messageType': 'regular',
            },
          ],
          'hasMore': false,
        },
      );

      final r = await api.list('r1', cachePolicy: CachePolicy.networkOnly);

      expect(r.isSuccess, true);
      // `old` is before clearedAt → filtered out, only `new` survives.
      expect(r.dataOrNull!.items.map((m) => m.id), ['new']);
    });

    test(
      'send() persists the confirmed message and invalidates cache',
      () async {
        when(
          () => rest.post(any(), data: any(named: 'data')),
        ).thenAnswer((_) async => syncEchoJson('m-sent'));

        final r = await api.send('r1', text: 'hi');

        expect(r.isSuccess, true);
        verify(() => cache.saveMessages('r1', any())).called(1);
      },
    );

    test('send() does NOT write an ack_mode=async provisional echo to the '
        'cache (its id never matches the stored message) but still '
        'invalidates the TTL keys', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => msgJson('m-provisional'));

      // Seed the messages TTL key as fresh so the invalidation is
      // observable through a cacheFirst probe below.
      await cacheManager.resolve<String>(
        key: 'messages:r1',
        ttl: const Duration(hours: 12),
        policy: CachePolicy.networkOnly,
        fromCache: () async => null,
        fromNetwork: () async => const ChatSuccess('seed'),
        saveToCache: (_) async {},
      );

      final r = await api.send('r1', text: 'hi');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.isProvisional, isTrue);
      verifyNever(() => cache.saveMessages(any(), any()));

      var probedNetwork = false;
      await cacheManager.resolve<String>(
        key: 'messages:r1',
        ttl: const Duration(hours: 12),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'stale-snapshot',
        fromNetwork: () async {
          probedNetwork = true;
          return const ChatSuccess('refetched');
        },
        saveToCache: (_) async {},
      );
      expect(
        probedNetwork,
        isTrue,
        reason:
            'the provisional send must still invalidate messages:r1 so the '
            'next read goes to the network for the authoritative row',
      );
    });

    test('update() walks the cache to refresh the existing entry', () async {
      when(() => cache.getMessages(any())).thenAnswer(
        (_) async => ChatSuccess(<ChatMessage>[
          ChatMessage(
            id: 'm-edit',
            from: 'u1',
            timestamp: DateTime(2026, 1, 1),
            text: 'before',
          ),
        ]),
      );
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.update('r1', 'm-edit', text: 'after');

      expect(r.isSuccess, true);
      verify(() => cache.updateMessage('r1', any())).called(1);
    });

    test('delete() removes from cache on success', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await api.delete('r1', 'm1');
      expect(r.isSuccess, true);
      verify(() => cache.deleteMessage('r1', 'm1')).called(1);
    });

    test(
      'markRoomAsRead() clears the unread cache + invalidates rooms',
      () async {
        when(
          () => rest.postVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        final r = await api.markRoomAsRead('r1', lastReadMessageId: 'm1');

        expect(r.isSuccess, true);
        verify(() => cache.deleteUnread('r1')).called(1);
      },
    );

    test('clearChat() sets clearedAt + clears cached messages', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.clearChat('r1');

      expect(r.isSuccess, true);
      verify(() => cache.setClearedAt('r1', any())).called(1);
      verify(() => cache.clearMessages('r1')).called(1);
    });

    test(
      'getRoomReceipts() with cache miss hits the network and saves',
      () async {
        when(() => rest.getWithTotalCount(any())).thenAnswer(
          (_) async => (
            {
              'receipts': [
                {'userId': 'u2', 'lastReadAt': '2026-01-02T00:00:00Z'},
              ],
              'hasMore': false,
            },
            1,
          ),
        );

        final r = await api.getRoomReceipts('r1');

        expect(r.isSuccess, true);
        expect(r.dataOrNull!.items, hasLength(1));
        verify(() => cache.saveReceipts('r1', any())).called(1);
      },
    );

    test(
      'getReactions() with networkOnly cachePolicy bypasses the cache',
      () async {
        when(() => cache.getReactions(any(), any())).thenAnswer(
          (_) async => const ChatSuccess(<AggregatedReaction>[
            AggregatedReaction(emoji: '👍', count: 1, users: ['u1']),
          ]),
        );
        when(() => rest.get(any())).thenAnswer(
          (_) async => {
            'reactions': [
              {
                'emoji': '❤️',
                'count': 2,
                'userIds': ['u1', 'u2'],
              },
            ],
          },
        );

        final r = await api.getReactions(
          'r1',
          'm1',
          cachePolicy: CachePolicy.networkOnly,
        );

        expect(r.isSuccess, true);
        // networkOnly bypasses the cache, so the new emoji takes over.
        expect(r.dataOrThrow.first.emoji, '❤️');
      },
    );

    test('pinMessage() invalidates the pins cache on success', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      final r = await api.pinMessage('r1', 'm1');
      expect(r.isSuccess, true);
    });

    test('unpinMessage() deletes pin from cache + invalidates', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await api.unpinMessage('r1', 'm1');
      expect(r.isSuccess, true);
      verify(() => cache.deletePin('r1', 'm1')).called(1);
    });

    test('send() invalidates rooms:all/rooms:unread BEFORE writing to cache, '
        'so a concurrent cacheFirst reader never observes a fresh TTL '
        'paired with a not-yet-updated cache entry', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => syncEchoJson('m-sent'));

      // Pre-populate the `rooms:all` TTL key so it starts out fresh, as
      // if some earlier read had just resolved it from the network.
      await cacheManager.resolve<String>(
        key: 'rooms:all',
        ttl: const Duration(hours: 12),
        policy: CachePolicy.networkOnly,
        fromCache: () async => null,
        fromNetwork: () async => const ChatSuccess('seed'),
        saveToCache: (_) async {},
      );

      String? orderOfEvents;
      // The concurrent reader's probe runs synchronously from inside the
      // mocked `saveMessages` call, i.e. strictly AFTER the fix's
      // invalidation step but strictly BEFORE the write it wraps
      // completes — exactly the interleaving core-5 describes. A
      // `cacheFirst` probe only returns the cached snapshot without
      // touching the network when the TTL key is still considered
      // fresh, so it directly observes whether the invalidation already
      // ran.
      when(() => cache.saveMessages(any(), any())).thenAnswer((_) async {
        var probedNetwork = false;
        await cacheManager.resolve<String>(
          key: 'rooms:all',
          ttl: const Duration(hours: 12),
          policy: CachePolicy.cacheFirst,
          fromCache: () async => 'stale-snapshot',
          fromNetwork: () async {
            probedNetwork = true;
            return const ChatSuccess('refetched');
          },
          saveToCache: (_) async {},
        );
        orderOfEvents = probedNetwork ? 'invalidated' : 'stale-visible';
        return const ChatSuccess(null);
      });

      final r = await api.send('r1', text: 'hi');

      expect(r.isSuccess, true);
      expect(
        orderOfEvents,
        'invalidated',
        reason:
            'rooms:all must already be invalidated by the time '
            'saveMessages() runs, closing the race window',
      );
    });

    test('listPins() falls through to network when cache empty', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'pins': [
              {
                'roomId': 'r1',
                'messageId': 'm1',
                'pinnedBy': 'u1',
                'pinnedAt': '2026-01-01T00:00:00Z',
              },
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.listPins('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.messageId, 'm1');
    });
  });
}
