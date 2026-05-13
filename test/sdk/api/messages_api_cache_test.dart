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
  late CacheManager cacheManager;
  late MessagesApi api;

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
    api = MessagesApi(rest: rest, cache: cache, cacheManager: cacheManager);

    // Permissive defaults for cache calls.
    when(
      () => cache.getMessages(
        any(),
        limit: any(named: 'limit'),
        before: any(named: 'before'),
        after: any(named: 'after'),
      ),
    ).thenAnswer((_) async => []);
    when(() => cache.saveMessages(any(), any())).thenAnswer((_) async {});
    when(() => cache.getClearedAt(any())).thenAnswer((_) async => null);
    when(() => cache.getReceipts(any())).thenAnswer((_) async => []);
    when(() => cache.saveReceipts(any(), any())).thenAnswer((_) async {});
    when(() => cache.getReactions(any(), any())).thenAnswer((_) async => []);
    when(
      () => cache.saveReactions(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(() => cache.getPins(any())).thenAnswer((_) async => []);
    when(() => cache.savePins(any(), any())).thenAnswer((_) async {});
    when(() => cache.deletePin(any(), any())).thenAnswer((_) async {});
    when(() => cache.updateMessage(any(), any())).thenAnswer((_) async {});
    when(() => cache.deleteMessage(any(), any())).thenAnswer((_) async {});
    when(() => cache.deleteUnread(any())).thenAnswer((_) async {});
    when(() => cache.setClearedAt(any(), any())).thenAnswer((_) async {});
    when(() => cache.clearMessages(any())).thenAnswer((_) async {});
    when(() => cache.clearPendingMessages(any())).thenAnswer((_) async {});
  });

  Map<String, dynamic> msgJson(String id) => {
    'id': id,
    'from': 'u1',
    'timestamp': '2026-01-01T00:00:00Z',
    'text': 't',
    'messageType': 'regular',
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
        () => cache.getMessages(
          any(),
          limit: any(named: 'limit'),
          before: any(named: 'before'),
          after: any(named: 'after'),
        ),
      ).thenAnswer(
        (_) async => [
          ChatMessage(
            id: 'c1',
            from: 'u1',
            timestamp: DateTime(2026, 1, 1),
            text: 'cached',
          ),
        ],
      );

      final r = await api.list('r1', cachePolicy: CachePolicy.cacheFirst);

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.id, 'c1');
    });

    test('list() respects clearedAt filtering', () async {
      when(
        () => cache.getClearedAt(any()),
      ).thenAnswer((_) async => DateTime(2026, 6, 1));
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
        ).thenAnswer((_) async => msgJson('m-sent'));

        final r = await api.send('r1', text: 'hi');

        expect(r.isSuccess, true);
        verify(() => cache.saveMessages('r1', any())).called(1);
      },
    );

    test('update() walks the cache to refresh the existing entry', () async {
      when(() => cache.getMessages(any())).thenAnswer(
        (_) async => [
          ChatMessage(
            id: 'm-edit',
            from: 'u1',
            timestamp: DateTime(2026, 1, 1),
            text: 'before',
          ),
        ],
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

    test('getReactions() with forceRefresh bypasses the cache', () async {
      when(() => cache.getReactions(any(), any())).thenAnswer(
        (_) async => [
          const AggregatedReaction(emoji: '👍', count: 1, users: ['u1']),
        ],
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

      final r = await api.getReactions('r1', 'm1', forceRefresh: true);

      expect(r.isSuccess, true);
      // The forceRefresh path goes to network, so the new emoji takes over.
      expect(r.dataOrNull!.first.emoji, '❤️');
    });

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
