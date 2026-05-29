import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/cache/cache_config.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/cache/cache_policy.dart';
import 'package:noma_chat/src/core/result.dart';

class _RecordingDatasource extends MemoryChatLocalDatasource {
  int loadCalls = 0;
  int saveCalls = 0;
  Map<String, DateTime> lastSaved = const <String, DateTime>{};

  @override
  Future<Map<String, DateTime>> loadCacheTimestamps() async {
    loadCalls++;
    return super.loadCacheTimestamps();
  }

  @override
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {
    saveCalls++;
    lastSaved = Map<String, DateTime>.of(timestamps);
    await super.saveCacheTimestamps(timestamps);
  }
}

Future<ChatResult<String>> _ok() async => const ChatSuccess('value');

Future<void> _populate(CacheManager m, String key) async {
  await m.resolve<String>(
    key: key,
    ttl: const Duration(hours: 1),
    policy: CachePolicy.networkOnly,
    fromCache: () async => null,
    fromNetwork: _ok,
    saveToCache: (_) async {},
  );
}

void main() {
  group('CacheManager persistence — restore', () {
    test('empty restore keeps cacheFirst going to network', () async {
      final ds = _RecordingDatasource();
      final manager = CacheManager(config: const CacheConfig(), datasource: ds);
      await manager.restore();

      var networkCalls = 0;
      final result = await manager.resolve<String>(
        key: 'rooms:list',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const ChatSuccess('network');
        },
        saveToCache: (_) async {},
      );

      expect(ds.loadCalls, 1);
      expect(networkCalls, 1);
      expect(result.dataOrNull, 'network');

      await manager.dispose();
    });

    test(
      'restore after save honours TTL as if no cold start happened',
      () async {
        final ds = _RecordingDatasource();
        final first = CacheManager(
          config: const CacheConfig(),
          datasource: ds,
          persistDebounce: const Duration(milliseconds: 20),
        );
        await first.restore();
        await _populate(first, 'rooms:list');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await first.dispose();

        expect(ds.saveCalls, greaterThanOrEqualTo(1));
        expect(ds.lastSaved.containsKey('rooms:list'), isTrue);

        final second = CacheManager(
          config: const CacheConfig(),
          datasource: ds,
        );
        await second.restore();

        var networkCalls = 0;
        final result = await second.resolve<String>(
          key: 'rooms:list',
          ttl: const Duration(hours: 1),
          policy: CachePolicy.cacheFirst,
          fromCache: () async => 'cached',
          fromNetwork: () async {
            networkCalls++;
            return const ChatSuccess('network');
          },
          saveToCache: (_) async {},
        );

        expect(networkCalls, 0, reason: 'restored TTL should serve from cache');
        expect(result.dataOrNull, 'cached');

        await second.dispose();
      },
    );

    test('restore is a no-op when no datasource is provided', () async {
      final manager = CacheManager(config: const CacheConfig());
      await manager.restore();
      await manager.dispose();
    });
  });

  group('CacheManager persistence — entry cap', () {
    test('1001 markFresh keys evict oldest (FIFO) to stay at 1000', () async {
      final ds = _RecordingDatasource();
      final manager = CacheManager(
        config: const CacheConfig(),
        datasource: ds,
        persistDebounce: const Duration(seconds: 5),
        maxEntries: 1000,
      );
      await manager.restore();

      for (var i = 0; i < 1001; i++) {
        await _populate(manager, 'key:$i');
      }

      await manager.dispose();

      expect(ds.lastSaved.length, 1000);
      expect(
        ds.lastSaved.containsKey('key:0'),
        isFalse,
        reason: 'oldest key must have been evicted by FIFO cap',
      );
      expect(
        ds.lastSaved.containsKey('key:1000'),
        isTrue,
        reason: 'newest key must remain in the timestamps map',
      );
    });
  });

  group('CacheManager persistence — debounce', () {
    test(
      '5 rapid markFresh calls collapse into a single save after debounce',
      () async {
        final ds = _RecordingDatasource();
        final manager = CacheManager(
          config: const CacheConfig(),
          datasource: ds,
          persistDebounce: const Duration(milliseconds: 80),
        );
        await manager.restore();

        for (var i = 0; i < 5; i++) {
          await _populate(manager, 'k$i');
        }

        expect(
          ds.saveCalls,
          0,
          reason: 'no save should happen before the debounce window elapses',
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(ds.saveCalls, 1, reason: '5 writes should coalesce into 1 save');
        expect(ds.lastSaved.length, 5);

        await manager.dispose();
      },
    );

    test('dispose flushes pending save synchronously', () async {
      final ds = _RecordingDatasource();
      final manager = CacheManager(
        config: const CacheConfig(),
        datasource: ds,
        persistDebounce: const Duration(seconds: 30),
      );
      await manager.restore();
      await _populate(manager, 'single');

      expect(ds.saveCalls, 0);
      await manager.dispose();
      expect(ds.saveCalls, 1, reason: 'dispose must flush dirty state');
      expect(ds.lastSaved.containsKey('single'), isTrue);
    });
  });
}
