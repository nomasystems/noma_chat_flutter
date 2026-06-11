import 'package:hive_ce/hive_ce.dart';

/// Per-room `msgId → boxKey` index used by [HiveChatDatasource] to
/// reach a message in O(1) given its server-side id.
///
/// Hive messages are stored under the composite key
/// `{ISO8601 timestamp}_{msgId}` so a sequential scan is sorted
/// chronologically. That layout is great for paginated reads but bad
/// for "give me the row with messageId X" — the SDK frequently asks
/// for that (edit, delete, mark-as-read, reaction toggle). This
/// index keeps the lookup constant-time.
///
/// The index is lazy: the first call to [getOrBuild] for a room
/// walks the box once to populate the map; subsequent calls hit the
/// cache.
///
/// Cohesion: this class also owns the key-encoding helpers
/// ([keyFor] / [extractId]) so callers don't reach into internals.
class MessageIdIndex {
  /// Normalizes [ts] to a millisecond-precision UTC ISO-8601 string so
  /// box keys and range cutoffs sort lexicographically == chronologically.
  ///
  /// `DateTime.toIso8601String()` omits the microsecond digits when they
  /// are zero, so a backend millisecond timestamp (`…000Z`) would
  /// otherwise sort AFTER a local microsecond one (`…000123Z`) because
  /// `'Z'` (0x5A) > `'1'` (0x31), inverting chronological order in the
  /// same millisecond. Truncating every timestamp to milliseconds keeps
  /// the fraction a fixed three digits. Every key/cutoff builder must go
  /// through this helper.
  static String normalizedIso(DateTime ts) =>
      DateTime.fromMillisecondsSinceEpoch(
        ts.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();

  /// Encodes a (timestamp, id) pair as the box key. ISO 8601 prefix
  /// makes lexicographic ordering == chronological.
  static String keyFor(DateTime timestamp, String id) =>
      '${normalizedIso(timestamp)}_$id';

  /// Extracts the message id from a box key produced by [keyFor].
  /// Returns `null` if the key is malformed.
  static String? extractId(String key) {
    final idx = key.indexOf('_');
    return idx >= 0 ? key.substring(idx + 1) : null;
  }

  final Map<String, Map<String, String>> _byRoom = {};

  /// Returns the room's index, building it on first access by
  /// scanning [box]'s keys.
  Map<String, String> getOrBuild(
    String roomId,
    Box<Map<dynamic, dynamic>> box,
  ) {
    final cached = _byRoom[roomId];
    if (cached != null) return cached;
    final index = <String, String>{};
    for (final key in box.keys.cast<String>()) {
      final msgId = extractId(key);
      if (msgId != null) index[msgId] = key;
    }
    _byRoom[roomId] = index;
    return index;
  }

  /// Returns the box key for [messageId] in [roomId], or `null` if
  /// the message isn't indexed.
  String? findKey(
    String roomId,
    Box<Map<dynamic, dynamic>> box,
    String messageId,
  ) => getOrBuild(roomId, box)[messageId];

  /// Updates the index for a write — `oldKey` is the previous box
  /// key (when the message moved due to a timestamp change),
  /// `newKey` is the new one.
  void recordWrite(String roomId, String messageId, String newKey) {
    final index = _byRoom[roomId];
    if (index != null) index[messageId] = newKey;
  }

  /// Removes a single message from the index after a delete.
  void removeMessage(String roomId, String messageId) {
    _byRoom[roomId]?.remove(messageId);
  }

  /// Removes every message in [keys] from the index — used by the
  /// FIFO eviction sweep so the index doesn't accumulate stale
  /// entries.
  void removeKeysFromRoom(String roomId, Iterable<String> keys) {
    final index = _byRoom[roomId];
    if (index == null) return;
    for (final key in keys) {
      final msgId = extractId(key);
      if (msgId != null) index.remove(msgId);
    }
  }

  /// Drops the entire index for [roomId]. Called when the room's
  /// box has been wiped (e.g. clearMessages, room left, schema
  /// migration).
  void invalidateRoom(String roomId) {
    _byRoom.remove(roomId);
  }

  /// Drops the index for the room behind [boxName] when [boxPrefix]
  /// matches. Called from [HiveBoxRegistry] when a corrupted message
  /// box is recreated.
  void invalidateBoxByPrefix(String boxName, String boxPrefix) {
    if (boxName.startsWith(boxPrefix)) {
      final roomId = boxName.substring(boxPrefix.length);
      _byRoom.remove(roomId);
    }
  }

  /// Drops every per-room index. Used by `clear()` on the
  /// datasource.
  void clear() => _byRoom.clear();

  /// Indexer for tests + the legacy `_msgIdIndex[roomId]` access
  /// pattern. Returns `null` if the room hasn't been indexed.
  Map<String, String>? operator [](String roomId) => _byRoom[roomId];
}
