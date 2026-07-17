import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart' show experimental;

import '../../core/result.dart';
import 'cache_config.dart';
import '../../cache/cache_policy.dart';
import '../../cache/local_datasource.dart';

@experimental
typedef MetricCallback =
    void Function(String metric, Map<String, dynamic> data);

class CacheManager {
  final CacheConfig config;
  final MetricCallback? onMetric;
  final ChatLocalDatasource? datasource;
  final Duration persistDebounce;
  final int maxEntries;

  final LinkedHashMap<String, DateTime> _timestamps =
      LinkedHashMap<String, DateTime>();
  Timer? _persistTimer;
  bool _dirty = false;
  bool _disposed = false;

  CacheManager({
    required this.config,
    this.onMetric,
    this.datasource,
    this.persistDebounce = const Duration(seconds: 5),
    this.maxEntries = 1000,
  }) : assert(maxEntries > 0, 'maxEntries must be > 0');

  CachePolicy get defaultPolicy => config.defaultReadPolicy;

  /// Loads previously-persisted TTL timestamps from [datasource] so
  /// `cacheFirst` honours the TTL across cold starts. Safe to call
  /// multiple times; the last call wins.
  Future<void> restore() async {
    if (_disposed || datasource == null) return;
    final loaded = await datasource!.loadCacheTimestamps();
    _timestamps
      ..clear()
      ..addAll(loaded);
    while (_timestamps.length > maxEntries) {
      _timestamps.remove(_timestamps.keys.first);
    }
  }

  Future<ChatResult<T>> resolve<T>({
    required String key,
    required Duration ttl,
    required Future<T?> Function() fromCache,
    required Future<ChatResult<T>> Function() fromNetwork,
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
          return ChatSuccess(cached);
        }
        onMetric?.call('cache_miss', {'key': key, 'policy': 'cacheOnly'});
        return const ChatFailureResult(
          NetworkFailure('No cached data available'),
        );

      case CachePolicy.networkFirst:
        final result = await fromNetwork();
        if (result.isSuccess) {
          await saveToCache(result.dataOrNull as T);
          _markFresh(key);
          return result;
        }
        final cached = await fromCache();
        if (cached != null) {
          onMetric?.call('cache_hit', {'key': key, 'policy': 'networkFirst'});
          return ChatSuccess(cached);
        }
        onMetric?.call('cache_miss', {'key': key, 'policy': 'networkFirst'});
        return result;

      case CachePolicy.cacheFirst:
        if (_isValid(key, ttl)) {
          final cached = await fromCache();
          if (cached != null) {
            onMetric?.call('cache_hit', {'key': key, 'policy': 'cacheFirst'});
            return ChatSuccess(cached);
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
            return ChatSuccess(stale);
          }
        }
        return cacheFirstResult;
    }
  }

  Future<ChatResult<T>> _fromNetworkAndCache<T>(
    String key,
    Future<ChatResult<T>> Function() fromNetwork,
    Future<void> Function(T data) saveToCache,
  ) async {
    final result = await fromNetwork();
    if (result.isSuccess) {
      await saveToCache(result.dataOrNull as T);
      _markFresh(key);
    }
    return result;
  }

  void _markFresh(String key) {
    _timestamps.remove(key);
    _timestamps[key] = DateTime.now();
    while (_timestamps.length > maxEntries) {
      _timestamps.remove(_timestamps.keys.first);
    }
    _schedulePersist();
  }

  void _schedulePersist() {
    if (datasource == null || _disposed) return;
    _dirty = true;
    _persistTimer ??= Timer(persistDebounce, _persist);
  }

  Future<void> _persist() async {
    _persistTimer = null;
    if (!_dirty) return;
    _dirty = false;
    final snapshot = Map<String, DateTime>.of(_timestamps);
    await datasource?.saveCacheTimestamps(snapshot);
  }

  bool _isValid(String key, Duration ttl) {
    final ts = _timestamps[key];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < ttl;
  }

  void invalidate(String key) {
    if (_timestamps.remove(key) != null) _schedulePersist();
  }

  /// Invalidates every key in [keys] as a single synchronous batch.
  ///
  /// Since [CacheManager] runs single-isolate and every method here is
  /// synchronous, this is equivalent to calling [invalidate] in a loop —
  /// but it schedules at most one persist instead of one per key, and
  /// gives callers a single call site to invalidate a group of TTL keys
  /// together (e.g. before a write-through cache update), which is easier
  /// to keep ordered correctly than several separate [invalidate] calls.
  void invalidateKeys(Iterable<String> keys) {
    var removedAny = false;
    for (final key in keys) {
      if (_timestamps.remove(key) != null) removedAny = true;
    }
    if (removedAny) _schedulePersist();
  }

  void invalidatePrefix(String prefix) {
    final before = _timestamps.length;
    _timestamps.removeWhere((k, _) => k == prefix || k.startsWith('$prefix:'));
    if (_timestamps.length != before) _schedulePersist();
  }

  void clear() {
    if (_timestamps.isEmpty) return;
    _timestamps.clear();
    _schedulePersist();
  }

  /// Flushes any pending persist write synchronously and stops the
  /// debounce timer. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _persistTimer?.cancel();
    _persistTimer = null;
    if (_dirty) {
      _dirty = false;
      final snapshot = Map<String, DateTime>.of(_timestamps);
      await datasource?.saveCacheTimestamps(snapshot);
    }
  }
}
