import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

/// Owns the open/close/recovery lifecycle of every Hive box used by
/// [HiveChatDatasource]. Extracted so the rest of the datasource can
/// just call `registry.box(name)` and not worry about cache
/// invariants, concurrent open dedupe, or corrupted-box recovery.
///
/// Concurrency:
///
/// - Two concurrent `box(name)` callers on a fresh name share the
///   same in-flight open future via `_pendingOpens`.
/// - Once the future resolves, the box lives in `_openBoxes` and
///   subsequent calls return it immediately.
///
/// Corruption recovery: if `Hive.openBox` throws, the registry
/// deletes the box from disk and reopens. The
/// [onBoxRecreated] hook lets the owning datasource invalidate any
/// in-memory indices keyed off this box (e.g. the message-id index).
class HiveBoxRegistry {
  HiveBoxRegistry({
    required HiveCipher? cipher,
    void Function(String message)? onWarning,
    void Function(String metric, Map<String, dynamic> data)? onMetric,
    void Function(String boxName)? onBoxRecreated,
  }) : _cipher = cipher,
       _onWarning = onWarning,
       _onMetric = onMetric,
       _onBoxRecreated = onBoxRecreated;

  final HiveCipher? _cipher;
  void Function(String message)? _onWarning;
  void Function(String metric, Map<String, dynamic> data)? _onMetric;
  final void Function(String boxName)? _onBoxRecreated;

  final Map<String, Box<Map<dynamic, dynamic>>> _openBoxes = {};
  final Map<String, Future<Box<Map<dynamic, dynamic>>>> _pendingOpens = {};

  /// Rewires the warning callback. The datasource sets it after
  /// construction so the chain reaches whatever logger / metrics
  /// pipeline the consumer wires up.
  set onWarning(void Function(String message)? value) => _onWarning = value;

  /// Rewires the metric callback. Same lifecycle as [onWarning].
  set onMetric(
    void Function(String metric, Map<String, dynamic> data)? value,
  ) => _onMetric = value;

  /// Returns the box named [name], opening it (and recovering from
  /// corruption) if needed. Concurrent callers share the same
  /// in-flight open future.
  Future<Box<Map<dynamic, dynamic>>> box(String name) async {
    final cached = _openBoxes[name];
    if (cached != null && cached.isOpen) return cached;
    if (_pendingOpens.containsKey(name)) {
      return _pendingOpens[name]!;
    }
    final future = _openBoxSafe(name);
    _pendingOpens[name] = future;
    return future;
  }

  /// Returns the already-open box, or `null` if it isn't open
  /// (without forcing it). Used by paths that want to avoid an open
  /// roundtrip when there's nothing to do.
  Box<Map<dynamic, dynamic>>? peek(String name) {
    final cached = _openBoxes[name];
    return cached != null && cached.isOpen ? cached : null;
  }

  /// Names of every box currently tracked by the registry — open or
  /// in-flight. Caller iterates a stable snapshot.
  Iterable<String> get trackedNames => _openBoxes.keys.toList();

  /// True when [name] is currently tracked. Cheap — doesn't force an
  /// open.
  bool isTracked(String name) => _openBoxes.containsKey(name);

  /// Calls `.clear()` on every currently-open box. Errors are
  /// surfaced via [onWarning] (per-box) but never thrown.
  Future<void> clearAll() async {
    for (final box in _openBoxes.values) {
      if (!box.isOpen) continue;
      try {
        await box.clear();
      } catch (e) {
        _onWarning?.call('Box clear failed: $e');
      }
    }
  }

  /// Forgets the in-memory reference to [name]. The caller is
  /// responsible for having `close()`d the box first.
  void forget(String name) {
    _openBoxes.remove(name);
  }

  /// Closes and removes every box owned by this registry. Best-
  /// effort — warnings are surfaced via [onWarning] but no exception
  /// escapes.
  Future<void> closeAll() async {
    for (final box in _openBoxes.values) {
      try {
        await box.close();
      } catch (e) {
        _onWarning?.call('Box close failed: $e');
      }
    }
    _openBoxes.clear();
    _pendingOpens.clear();
  }

  /// Deletes [name] from disk and drops it from the registry.
  /// Returns `true` on success. Best-effort.
  Future<bool> deleteFromDisk(String name) async {
    try {
      final box = _openBoxes[name];
      if (box != null && box.isOpen) await box.close();
      _openBoxes.remove(name);
      await Hive.deleteBoxFromDisk(name);
      return true;
    } catch (e) {
      _onWarning?.call('Failed to delete box "$name": $e');
      return false;
    }
  }

  Future<Box<Map<dynamic, dynamic>>> _openBoxSafe(String name) async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(
        name,
        encryptionCipher: _cipher,
      );
      _openBoxes[name] = box;
      _pendingOpens.remove(name);
      return box;
    } catch (e) {
      _onWarning?.call('Box "$name" corrupted, deleting and recreating: $e');
      _onMetric?.call('box_corrupted', {'box': name, 'error': '$e'});
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteErr) {
        _onWarning?.call('Failed to delete corrupted box "$name": $deleteErr');
        _onMetric?.call('box_delete_failed', {
          'box': name,
          'error': '$deleteErr',
        });
      }
      try {
        final box = await Hive.openBox<Map<dynamic, dynamic>>(
          name,
          encryptionCipher: _cipher,
        );
        _openBoxes[name] = box;
        _pendingOpens.remove(name);
        _onBoxRecreated?.call(name);
        return box;
      } catch (e2) {
        _onWarning?.call('Failed to reopen box "$name" after recreation: $e2');
        _onMetric?.call('box_reopen_failed', {'box': name, 'error': '$e2'});
        _pendingOpens.remove(name);
        rethrow;
      }
    }
  }
}
