import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '_box_registry.dart';
import '_message_eviction_policy.dart';
import '_message_id_index.dart';
import 'serialization.dart';

/// Per-room message persistence on top of Hive: messages, pending
/// outbox, reactions, pins, receipts, and the per-room `clearedAt`
/// watermark.
///
/// Box layout:
/// - One messages box per room (key = `{ISO8601 timestamp}_{msgId}`),
///   pending outbox box per room (key = `msgId`) and a reactions box
///   per room (key = `msgId`).
/// - Pins and receipts share global boxes keyed by `roomId`.
/// - The `clearedAt_<roomId>` watermark lives in the shared meta box.
///
/// Per-room serialization is the composer's responsibility — methods
/// that mutate the message index ([save], [update], [delete], [clear])
/// expect the caller to wrap them in `withRoomLock`.
class MessageHiveStorage {
  MessageHiveStorage({
    required HiveBoxRegistry registry,
    required Box<Map<dynamic, dynamic>> metaBox,
    required MessageIdIndex index,
    required MessageEvictionPolicy eviction,
    required String messagesBoxPrefix,
    required String pendingBoxPrefix,
    required String reactionsBoxPrefix,
    required String pinsBoxName,
    required String receiptsBoxName,
    required Future<void> Function(String roomId) trackRoom,
    required Future<void> Function(String roomId) untrackRoom,
    required Future<void> Function(
      String operation,
      Future<void> Function() action,
    )
    safeWrite,
    required List<T> Function<T>(
      Iterable<Map<dynamic, dynamic>> values,
      T Function(Map<String, dynamic>) fromMap, {
      String? boxName,
    })
    safeDeserialize,
    void Function(String message)? Function()? warningFor,
  }) : _registry = registry,
       _metaBox = metaBox,
       _index = index,
       _eviction = eviction,
       _messagesBoxPrefix = messagesBoxPrefix,
       _pendingBoxPrefix = pendingBoxPrefix,
       _reactionsBoxPrefix = reactionsBoxPrefix,
       _pinsBoxName = pinsBoxName,
       _receiptsBoxName = receiptsBoxName,
       _trackRoom = trackRoom,
       _untrackRoom = untrackRoom,
       _safeWrite = safeWrite,
       _safeDeserialize = safeDeserialize,
       _warningFor = warningFor;

  final HiveBoxRegistry _registry;
  final Box<Map<dynamic, dynamic>> _metaBox;
  final MessageIdIndex _index;
  final MessageEvictionPolicy _eviction;
  final String _messagesBoxPrefix;
  final String _pendingBoxPrefix;
  final String _reactionsBoxPrefix;
  final String _pinsBoxName;
  final String _receiptsBoxName;
  final Future<void> Function(String roomId) _trackRoom;
  final Future<void> Function(String roomId) _untrackRoom;
  final Future<void> Function(String operation, Future<void> Function() action)
  _safeWrite;
  final List<T> Function<T>(
    Iterable<Map<dynamic, dynamic>> values,
    T Function(Map<String, dynamic>) fromMap, {
    String? boxName,
  })
  _safeDeserialize;
  final void Function(String message)? Function()? _warningFor;

  /// Box name resolver — exposed so cascades (deleteRoom, evict) can
  /// reach the right box from the composer.
  String messagesBoxName(String roomId) =>
      '$_messagesBoxPrefix${_sanitize(roomId)}';

  /// Pending box name resolver. Used by cascades that drop a room.
  String pendingBoxName(String roomId) =>
      '$_pendingBoxPrefix${_sanitize(roomId)}';

  /// Reactions box name resolver. Used by cascades that drop a room.
  String reactionsBoxName(String roomId) =>
      '$_reactionsBoxPrefix${_sanitize(roomId)}';

  static String _sanitize(String input) =>
      input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  Future<Box<Map<dynamic, dynamic>>> _box(String name) => _registry.box(name);

  Future<Box<Map<dynamic, dynamic>>> _messagesBox(String roomId) async {
    final name = messagesBoxName(roomId);
    await _trackRoom(roomId);
    return _box(name);
  }

  Future<Box<Map<dynamic, dynamic>>> _pendingBox(String roomId) =>
      _box(pendingBoxName(roomId));

  Future<Box<Map<dynamic, dynamic>>> _reactionsBox(String roomId) =>
      _box(reactionsBoxName(roomId));

  Future<Box<Map<dynamic, dynamic>>> _pinsBox() => _box(_pinsBoxName);
  Future<Box<Map<dynamic, dynamic>>> _receiptsBox() => _box(_receiptsBoxName);

  /// Persists [messages] in the per-room box. Dedupes against the
  /// existing [MessageIdIndex] so re-saving a message with a new
  /// timestamp drops the stale row. Caller must hold the per-room
  /// lock.
  Future<void> save(String roomId, List<ChatMessage> messages) async {
    final box = await _messagesBox(roomId);
    final index = _index.getOrBuild(roomId, box);
    final entries = <String, Map<dynamic, dynamic>>{};
    final keysToRemove = <String>[];
    for (final msg in messages) {
      final newKey = MessageIdIndex.keyFor(msg.timestamp, msg.id);
      final existingKey = index[msg.id];
      if (existingKey != null && existingKey != newKey) {
        keysToRemove.add(existingKey);
      }
      entries[newKey] = messageToMap(msg);
      index[msg.id] = newKey;
    }
    if (keysToRemove.isNotEmpty) {
      await _safeWrite('saveMessages dedup', () => box.deleteAll(keysToRemove));
    }
    await _safeWrite('saveMessages', () => box.putAll(entries));
    await _eviction.evictIfNeeded(box, roomId: roomId);
  }

  /// Returns messages newest-first respecting [limit], [before],
  /// [after] cursors and the room's `clearedAt` watermark.
  Future<List<ChatMessage>> get(
    String roomId, {
    int? limit,
    String? before,
    String? after,
  }) async {
    final box = await _messagesBox(roomId);
    var keys = box.keys.cast<String>().toList();

    final clearedAt = await getClearedAt(roomId);
    if (clearedAt != null) {
      final cutoff = '${clearedAt.toUtc().toIso8601String()}_￿';
      keys = keys.where((k) => k.compareTo(cutoff) > 0).toList();
    }

    final onWarning = _warningFor?.call();

    if (before != null) {
      final beforeTime = DateTime.tryParse(before);
      if (beforeTime == null) {
        onWarning?.call('Invalid before cursor (not a timestamp): $before');
        return <ChatMessage>[];
      }
      final cutoffPrefix = beforeTime.toUtc().toIso8601String();
      keys = keys.where((k) => k.compareTo(cutoffPrefix) < 0).toList();
    }

    if (after != null) {
      final afterTime = DateTime.tryParse(after);
      if (afterTime == null) {
        onWarning?.call('Invalid after cursor (not a timestamp): $after');
        return <ChatMessage>[];
      }
      final cutoff = '${afterTime.toUtc().toIso8601String()}_￿';
      keys = keys.where((k) => k.compareTo(cutoff) > 0).toList();
    }

    final selected = limit != null && keys.length > limit
        ? keys.sublist(keys.length - limit)
        : keys;

    final result = <ChatMessage>[];
    for (final key in selected.reversed) {
      final data = box.get(key);
      if (data == null) continue;
      try {
        result.add(
          messageFromMap(Map<String, dynamic>.from(data), onWarning: onWarning),
        );
      } catch (e) {
        onWarning?.call('Skipped corrupted message at key "$key": $e');
      }
    }
    return result;
  }

  /// Updates a single message in place. Caller must hold the per-room
  /// lock.
  Future<void> update(String roomId, ChatMessage message) async {
    final name = messagesBoxName(roomId);
    final box = await _box(name);
    final key = _index.findKey(roomId, box, message.id);
    if (key != null) {
      await _safeWrite(
        'updateMessage',
        () => box.put(key, messageToMap(message)),
      );
    }
  }

  /// Deletes a single message by id. Caller must hold the per-room
  /// lock.
  Future<void> delete(String roomId, String messageId) async {
    final box = await _messagesBox(roomId);
    final key = _index.findKey(roomId, box, messageId);
    if (key != null) {
      await _safeWrite('deleteMessage', () => box.delete(key));
      _index.removeMessage(roomId, messageId);
    }
  }

  /// Wipes every message in the room's box and clears the in-memory
  /// index entry. Caller must hold the per-room lock.
  Future<void> clear(String roomId) async {
    final name = messagesBoxName(roomId);
    final box = await _box(name);
    await _safeWrite('clearMessages', () => box.clear());
    _index.invalidateRoom(roomId);
    await _untrackRoom(roomId);
  }

  /// Persists [message] in the pending outbox. [isFailed] flags it as
  /// a definitive send failure (vs. still in flight).
  Future<void> savePending(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async {
    final box = await _pendingBox(roomId);
    final entry = {'message': messageToMap(message), 'isFailed': isFailed};
    await _safeWrite('savePendingMessage', () => box.put(message.id, entry));
  }

  /// Returns the pending outbox sorted chronologically.
  Future<List<PendingChatMessage>> getPending(String roomId) async {
    final box = await _pendingBox(roomId);
    final onWarning = _warningFor?.call();
    final result = <PendingChatMessage>[];
    for (final raw in box.values) {
      try {
        final entry = Map<String, dynamic>.from(raw);
        final msgMap = Map<String, dynamic>.from(entry['message'] as Map);
        final msg = messageFromMap(msgMap, onWarning: onWarning);
        final isFailed = entry['isFailed'] == true;
        result.add(PendingChatMessage(msg, isFailed: isFailed));
      } catch (e) {
        onWarning?.call('Skipped corrupted pending message: $e');
      }
    }
    result.sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));
    return result;
  }

  /// Drops a single entry from the pending outbox.
  Future<void> deletePending(String roomId, String messageId) async {
    final box = await _pendingBox(roomId);
    if (box.containsKey(messageId)) {
      await _safeWrite('deletePendingMessage', () => box.delete(messageId));
    }
  }

  /// Wipes the room's pending outbox.
  Future<void> clearPending(String roomId) async {
    final box = await _pendingBox(roomId);
    await _safeWrite('clearPendingMessages', () => box.clear());
  }

  /// Stamps the `clearedAt` watermark for [roomId] so subsequent
  /// reads from [get] hide rows older than [timestamp].
  Future<void> setClearedAt(String roomId, DateTime timestamp) async {
    await _safeWrite(
      'setClearedAt',
      () => _metaBox.put('clearedAt_$roomId', {
        'ts': timestamp.toUtc().toIso8601String(),
      }),
    );
  }

  /// Reads the `clearedAt` watermark or `null` if none was stamped.
  Future<DateTime?> getClearedAt(String roomId) async {
    final data = _metaBox.get('clearedAt_$roomId');
    if (data == null) return null;
    final ts = data['ts'] as String?;
    if (ts == null) return null;
    return DateTime.tryParse(ts);
  }

  /// Drops the `clearedAt` watermark. Used by cascades.
  Future<void> deleteClearedAt(String roomId) async {
    await _safeWrite(
      'deleteClearedAt',
      () => _metaBox.delete('clearedAt_$roomId'),
    );
  }

  /// Persists [reactions] for [messageId] in [roomId]. Overwrites the
  /// existing aggregate.
  Future<void> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  ) async {
    final box = await _reactionsBox(roomId);
    await _safeWrite(
      'saveReactions',
      () =>
          box.put(messageId, {'items': reactions.map(reactionToMap).toList()}),
    );
  }

  /// Returns the aggregated reactions for [messageId].
  Future<List<AggregatedReaction>> getReactions(
    String roomId,
    String messageId,
  ) async {
    final box = await _reactionsBox(roomId);
    final raw = box.get(messageId);
    if (raw == null) return <AggregatedReaction>[];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(
      items,
      (m) => reactionFromMap(m),
      boxName: 'reactions',
    );
  }

  /// Drops the reaction aggregate for [messageId].
  Future<void> deleteReactions(String roomId, String messageId) async {
    final box = await _reactionsBox(roomId);
    await _safeWrite('deleteReactions', () => box.delete(messageId));
  }

  /// Wipes every reaction in the room. Used by cascades.
  Future<void> clearReactions(String roomId) async {
    final box = await _reactionsBox(roomId);
    await _safeWrite('clearReactions', () => box.clear());
  }

  /// Persists pin list for [roomId]. Overwrites the existing list.
  Future<void> savePins(String roomId, List<MessagePin> pins) async {
    final box = await _pinsBox();
    await _safeWrite(
      'savePins',
      () => box.put(roomId, {'items': pins.map(pinToMap).toList()}),
    );
  }

  /// Returns pins for [roomId].
  Future<List<MessagePin>> getPins(String roomId) async {
    final box = await _pinsBox();
    final raw = box.get(roomId);
    if (raw == null) return <MessagePin>[];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(items, (m) => pinFromMap(m), boxName: 'pins');
  }

  /// Removes a single pin by [messageId] inside [roomId].
  Future<void> deletePin(String roomId, String messageId) async {
    final box = await _pinsBox();
    final raw = box.get(roomId);
    if (raw == null) return;
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    final filtered = items
        .where((m) => Map<String, dynamic>.from(m)['messageId'] != messageId)
        .toList();
    await _safeWrite('deletePin', () => box.put(roomId, {'items': filtered}));
  }

  /// Drops every pin for [roomId]. Used by cascades.
  Future<void> clearPinsForRoom(String roomId) async {
    final box = await _pinsBox();
    await _safeWrite('clearPinsForRoom', () => box.delete(roomId));
  }

  /// Persists [receipts] for [roomId]. Overwrites the existing list.
  Future<void> saveReceipts(String roomId, List<ReadReceipt> receipts) async {
    final box = await _receiptsBox();
    await _safeWrite(
      'saveReceipts',
      () => box.put(roomId, {'items': receipts.map(receiptToMap).toList()}),
    );
  }

  /// Returns read receipts for [roomId].
  Future<List<ReadReceipt>> getReceipts(String roomId) async {
    final box = await _receiptsBox();
    final raw = box.get(roomId);
    if (raw == null) return <ReadReceipt>[];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(
      items,
      (m) => receiptFromMap(m),
      boxName: 'receipts',
    );
  }

  /// Drops every receipt for [roomId]. Used by cascades.
  Future<void> clearReceiptsForRoom(String roomId) async {
    final box = await _receiptsBox();
    await _safeWrite('clearReceiptsForRoom', () => box.delete(roomId));
  }
}
