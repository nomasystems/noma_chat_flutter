import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CacheManager manager;

  setUp(() {
    manager = CacheManager(config: const CacheConfig());
  });

  group('CacheManager.resolve', () {
    test('networkOnly always calls network and caches result', () async {
      var networkCalls = 0;
      String? savedValue;

      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkOnly,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('network');
        },
        saveToCache: (data) async => savedValue = data,
      );

      expect(result.dataOrNull, 'network');
      expect(networkCalls, 1);
      expect(savedValue, 'network');
    });

    test('cacheOnly returns cached data without calling network', () async {
      var networkCalls = 0;

      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheOnly,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('network');
        },
        saveToCache: (data) async {},
      );

      expect(result.dataOrNull, 'cached');
      expect(networkCalls, 0);
    });

    test('cacheOnly returns failure when no cached data', () async {
      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheOnly,
        fromCache: () async => null,
        fromNetwork: () async => const Success('network'),
        saveToCache: (data) async {},
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });

    test('networkFirst falls back to cache on network failure', () async {
      // First call to populate timestamp
      await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async => const Success('network'),
        saveToCache: (data) async {},
      );

      // Second call with network failure
      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async =>
            const Failure(NetworkFailure('no connection')),
        saveToCache: (data) async {},
      );

      expect(result.dataOrNull, 'cached');
    });

    test('networkFirst returns network error when no cache available',
        () async {
      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkFirst,
        fromCache: () async => null,
        fromNetwork: () async =>
            const Failure(NetworkFailure('no connection')),
        saveToCache: (data) async {},
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });

    test('cacheFirst returns cache when valid', () async {
      var networkCalls = 0;

      // First call populates cache timestamp
      await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkOnly,
        fromCache: () async => null,
        fromNetwork: () async {
          networkCalls++;
          return const Success('network');
        },
        saveToCache: (data) async {},
      );

      // Second call should use cache
      final result = await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('network2');
        },
        saveToCache: (data) async {},
      );

      expect(result.dataOrNull, 'cached');
      expect(networkCalls, 1);
    });

    test('cacheFirst falls back to network when cache expired', () async {
      var networkCalls = 0;

      // Use zero TTL so cache is always expired
      final result = await manager.resolve<String>(
        key: 'expired-test',
        ttl: Duration.zero,
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('network');
        },
        saveToCache: (data) async {},
      );

      expect(result.dataOrNull, 'network');
      expect(networkCalls, 1);
    });

    test('invalidate removes cache entry', () async {
      // Populate
      await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.networkOnly,
        fromCache: () async => null,
        fromNetwork: () async => const Success('v1'),
        saveToCache: (data) async {},
      );

      manager.invalidate('test');

      // cacheFirst should go to network since invalidated
      var networkCalls = 0;
      await manager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('v2');
        },
        saveToCache: (data) async {},
      );

      expect(networkCalls, 1);
    });

    test('invalidatePrefix removes matching entries', () async {
      for (final key in ['messages:room1:a', 'messages:room1:b', 'users:1']) {
        await manager.resolve<String>(
          key: key,
          ttl: const Duration(hours: 1),
          policy: CachePolicy.networkOnly,
          fromCache: () async => null,
          fromNetwork: () async => const Success('v'),
          saveToCache: (data) async {},
        );
      }

      manager.invalidatePrefix('messages:room1');

      // messages keys invalidated, users key still valid
      var networkCalls = 0;
      await manager.resolve<String>(
        key: 'messages:room1:a',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('v2');
        },
        saveToCache: (data) async {},
      );
      expect(networkCalls, 1);

      networkCalls = 0;
      await manager.resolve<String>(
        key: 'users:1',
        ttl: const Duration(hours: 1),
        policy: CachePolicy.cacheFirst,
        fromCache: () async => 'cached',
        fromNetwork: () async {
          networkCalls++;
          return const Success('v2');
        },
        saveToCache: (data) async {},
      );
      expect(networkCalls, 0);
    });

    test('uses defaultPolicy when no policy specified', () async {
      final customManager = CacheManager(
        config: const CacheConfig(defaultReadPolicy: CachePolicy.cacheOnly),
      );

      final result = await customManager.resolve<String>(
        key: 'test',
        ttl: const Duration(hours: 1),
        fromCache: () async => 'cached',
        fromNetwork: () async => const Success('network'),
        saveToCache: (data) async {},
      );

      expect(result.dataOrNull, 'cached');
    });
  });
}
