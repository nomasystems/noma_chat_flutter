import '../../core/result.dart';
import 'cache_config.dart';
import 'cache_policy.dart';

typedef MetricCallback =
    void Function(String metric, Map<String, dynamic> data);

class CacheManager {
  final CacheConfig config;
  final MetricCallback? onMetric;
  final Map<String, DateTime> _timestamps = {};

  CacheManager({required this.config, this.onMetric});

  CachePolicy get defaultPolicy => config.defaultReadPolicy;

  Future<Result<T>> resolve<T>({
    required String key,
    required Duration ttl,
    required Future<T?> Function() fromCache,
    required Future<Result<T>> Function() fromNetwork,
    required Future<void> Function(T data) saveToCache,
    CachePolicy? policy,
  }) async {
    final effectivePolicy = policy ?? config.defaultReadPolicy;

    switch (effectivePolicy) {
      case CachePolicy.networkOnly:
        return _fromNetworkAndCache(key, fromNetwork, saveToCache);

      case CachePolicy.cacheOnly:
        final cached = await fromCache();
        if (cached != null) {
          onMetric?.call('cache_hit', {'key': key, 'policy': 'cacheOnly'});
          return Success(cached);
        }
        onMetric?.call('cache_miss', {'key': key, 'policy': 'cacheOnly'});
        return const Failure(NetworkFailure('No cached data available'));

      case CachePolicy.networkFirst:
        final result = await fromNetwork();
        if (result.isSuccess) {
          await saveToCache(result.dataOrNull as T);
          _timestamps[key] = DateTime.now();
          return result;
        }
        final cached = await fromCache();
        if (cached != null) {
          onMetric?.call('cache_hit', {'key': key, 'policy': 'networkFirst'});
          return Success(cached);
        }
        onMetric?.call('cache_miss', {'key': key, 'policy': 'networkFirst'});
        return result;

      case CachePolicy.cacheFirst:
        if (_isValid(key, ttl)) {
          final cached = await fromCache();
          if (cached != null) {
            onMetric?.call('cache_hit', {'key': key, 'policy': 'cacheFirst'});
            return Success(cached);
          }
        }
        final cacheFirstResult = await _fromNetworkAndCache(
          key,
          fromNetwork,
          saveToCache,
        );
        if (cacheFirstResult.isFailure) {
          final stale = await fromCache();
          if (stale != null) {
            onMetric?.call('cache_stale_fallback', {
              'key': key,
              'policy': 'cacheFirst',
            });
            return Success(stale);
          }
        }
        return cacheFirstResult;
    }
  }

  Future<Result<T>> _fromNetworkAndCache<T>(
    String key,
    Future<Result<T>> Function() fromNetwork,
    Future<void> Function(T data) saveToCache,
  ) async {
    final result = await fromNetwork();
    if (result.isSuccess) {
      await saveToCache(result.dataOrNull as T);
      _timestamps[key] = DateTime.now();
    }
    return result;
  }

  bool _isValid(String key, Duration ttl) {
    final ts = _timestamps[key];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < ttl;
  }

  void invalidate(String key) => _timestamps.remove(key);

  void invalidatePrefix(String prefix) {
    _timestamps.removeWhere((k, _) => k == prefix || k.startsWith('$prefix:'));
  }

  void clear() => _timestamps.clear();
}
