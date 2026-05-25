import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

import '_message_id_index.dart';

/// FIFO + TTL eviction for per-room message boxes.
///
/// **FIFO** ([evictIfNeeded]): once a room's box exceeds
/// [maxPerRoom], delete the oldest entries until the count matches.
/// Keys are `{ISO8601 timestamp}_{id}` so alphabetic ordering ==
/// chronological — the head of the sorted key list is always the
/// oldest.
///
/// **TTL** ([expireOldMessages]): scan every tracked room box and
/// delete keys whose timestamp prefix is older than `now - [ttl]`.
/// Same insight — keys are sorted, so a simple lexicographic compare
/// against the cutoff prefix is enough.
///
/// Both paths invalidate the [MessageIdIndex] so it stays in sync
/// with the underlying box.
class MessageEvictionPolicy {
  MessageEvictionPolicy({
    required this.maxPerRoom,
    required this.ttl,
    required this.checkInterval,
    required this.index,
    required this.safeWrite,
    required this.onMetric,
  });

  /// Soft cap for messages stored per room — exceeding it triggers
  /// FIFO eviction in [evictIfNeeded].
  final int maxPerRoom;

  /// Optional TTL — when set, messages older than `now - ttl` are
  /// evicted by [expireOldMessages]. Pass `null` to disable.
  final Duration? ttl;

  /// Optional periodic TTL sweep interval — used by [startTtlTimer].
  final Duration? checkInterval;

  /// In-memory index that must be kept in sync when entries leave the
  /// box.
  final MessageIdIndex index;

  /// Wrapper used by [HiveChatDatasource] to swallow Hive write
  /// errors and route them to its logger.
  final Future<void> Function(String operation, Future<void> Function() action)
  safeWrite;

  /// Telemetry hook — gets `cache_eviction` / `cache_ttl_expired`.
  final void Function(String metric, Map<String, dynamic> data)? onMetric;

  Timer? _ttlTimer;

  /// FIFO eviction: if [box]'s length exceeds [maxPerRoom], delete
  /// the oldest entries (by key order). When [roomId] is supplied,
  /// the [index] is updated to drop the corresponding ids.
  Future<void> evictIfNeeded(
    Box<Map<dynamic, dynamic>> box, {
    String? roomId,
  }) async {
    if (box.length <= maxPerRoom) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxPerRoom);
    await safeWrite('evictOldMessages', () => box.deleteAll(toRemove));
    if (roomId != null) {
      index.removeKeysFromRoom(roomId, toRemove);
    }
    onMetric?.call('cache_eviction', {
      'entity': 'messages',
      'count': toRemove.length,
    });
  }

  /// TTL sweep: for every roomId in [trackedRoomIds], drop keys older
  /// than `now - [ttl]`. [boxFor] returns the open box for a roomId.
  /// No-op when [ttl] is null.
  Future<void> expireOldMessages({
    required Iterable<String> trackedRoomIds,
    required Future<Box<Map<dynamic, dynamic>>> Function(String roomId) boxFor,
  }) async {
    if (ttl == null) return;
    final cutoffPrefix = DateTime.now()
        .toUtc()
        .subtract(ttl!)
        .toIso8601String();
    for (final roomId in trackedRoomIds) {
      final box = await boxFor(roomId);
      // Keys are `{timestamp}_{id}`, sorted ascending — every key
      // lexicographically smaller than the cutoff prefix is expired.
      final keysToRemove = box.keys
          .cast<String>()
          .where((k) => k.compareTo(cutoffPrefix) < 0)
          .toList();
      if (keysToRemove.isNotEmpty) {
        await safeWrite('expireOldMessages', () => box.deleteAll(keysToRemove));
        onMetric?.call('cache_ttl_expired', {
          'roomId': roomId,
          'count': keysToRemove.length,
        });
      }
    }
  }

  /// Starts the periodic TTL sweep timer. The caller passes an
  /// [isAlive] predicate (typically a closure over the datasource's
  /// disposed flag) and a [trigger] callback that performs the TTL
  /// sweep. No-op when [checkInterval] is null.
  void startTtlTimer({
    required bool Function() isAlive,
    required Future<void> Function() trigger,
  }) {
    if (checkInterval == null) return;
    _ttlTimer = Timer.periodic(checkInterval!, (_) {
      if (isAlive()) trigger();
    });
  }

  /// Cancels the periodic TTL timer, if any.
  void stopTtlTimer() {
    _ttlTimer?.cancel();
    _ttlTimer = null;
  }
}
