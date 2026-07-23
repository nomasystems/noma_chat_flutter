import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// Stamps + advances the cache `schemaVersion` key inside Hive's meta
/// box, calling the registered [migrations] step-by-step or falling back
/// to [wipeStrategy] when no migration path is available.
///
/// Failures are best-effort: a migration that throws surfaces via the
/// [Hive.openBox]-level error path, never silently. Wipe failures are
/// logged through [onWarning] and the stored schema version is left
/// untouched so the next launch tries again.
class CacheSchemaMigrator {
  CacheSchemaMigrator({
    required this.metaBox,
    required this.targetVersion,
    required this.migrations,
    required this.wipeStrategy,
    required this.versionKey,
    this.onWarning,
    this.onMetric,
  });

  /// The `chat_meta` Hive box that holds the persisted schema version
  /// (and other adapter-level scalars).
  final Box<Map<dynamic, dynamic>> metaBox;

  /// Version this build of the SDK expects the cache to be at.
  /// Mismatch (stored < target) triggers a step-by-step migration;
  /// stored > target (downgrade) wipes the cache.
  final int targetVersion;

  /// Migration callbacks keyed by the version they upgrade INTO
  /// (`migrations[2]` runs to go from v1 → v2). Each migration is
  /// awaited before advancing to the next.
  @visibleForTesting
  final Map<int, Future<void> Function()> migrations;

  /// Strategy used when the stored version is unknown / no migration
  /// path is registered / a downgrade is detected. Typical impl opens
  /// the core boxes and calls `datasource.clear()`.
  final Future<void> Function() wipeStrategy;

  /// Key under which the schema version is stored inside [metaBox].
  /// Made configurable for tests.
  final String versionKey;

  /// Optional `(level, message)` warning sink. Called on each wipe
  /// path so consumers can log the loss of cache.
  final void Function(String level, String message)? onWarning;

  /// Optional metric sink. Currently emits `schema_migration_wipe`
  /// with `{from, to, reason}` tags whenever a wipe path runs.
  final void Function(String name, Map<String, dynamic> tags)? onMetric;

  /// Reads the stored schema version, advances it through the
  /// registered migrations (or wipes the cache when no path is
  /// available), and stamps [targetVersion] back into the meta box.
  ///
  /// Idempotent — repeated calls with `stored == target` short-circuit
  /// to a no-op. Always returns normally; a thrown migration is the
  /// caller's responsibility to handle (the cache stays unstamped so
  /// the next launch retries).
  Future<void> migrateIfNeeded() async {
    // Read defensively: a corrupted meta box entry (bit flip, partial
    // write cut short by a kill mid-`put`, or a future/foreign format)
    // can hand back a value that isn't a Map at all, or a `version` of
    // an unexpected type. `Box<Map>.get()` itself casts to `Map?`
    // internally and throws a TypeError when the decoded value doesn't
    // match, and an `as int?` on a wrong-typed `version` field would
    // throw too — either one happening here, before any box is even
    // open, would crash the whole `HiveChatDatasource.create()` startup
    // path instead of just leaving this cache treated as unversioned.
    Map<dynamic, dynamic>? stored;
    try {
      stored = metaBox.get(versionKey);
    } catch (_) {
      stored = null;
    }
    final rawVersion = stored is Map ? stored['version'] : null;
    final storedVersion = rawVersion is int ? rawVersion : 0;
    if (storedVersion == targetVersion) return;

    if (storedVersion < targetVersion) {
      var v = storedVersion;
      while (v < targetVersion) {
        final nextVersion = v + 1;
        final migration = migrations[nextVersion];
        if (migration != null) {
          await migration();
        } else {
          onWarning?.call(
            'warn',
            'Schema migration: no migration from v$storedVersion '
                'to v$targetVersion, wiping cache',
          );
          onMetric?.call('schema_migration_wipe', {
            'from': storedVersion,
            'to': targetVersion,
            'reason': 'no_migration_path',
          });
          await wipeStrategy();
          break;
        }
        v = nextVersion;
      }
    } else {
      onWarning?.call(
        'warn',
        'Schema migration: downgrade from v$storedVersion '
            'to v$targetVersion, wiping cache',
      );
      onMetric?.call('schema_migration_wipe', {
        'from': storedVersion,
        'to': targetVersion,
        'reason': 'downgrade',
      });
      await wipeStrategy();
    }

    await metaBox.put(versionKey, {'version': targetVersion});
  }
}
