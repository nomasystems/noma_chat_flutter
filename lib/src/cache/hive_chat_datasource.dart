import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:flutter/foundation.dart';

import '../core/result.dart';
import '../models/contact.dart';
import '../models/invited_room.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/room.dart';
import '../models/unread_room.dart';
import '../models/user.dart';
import 'local_datasource.dart';
import '_box_registry.dart';
import '_message_eviction_policy.dart';
import '_message_id_index.dart';
import '_schema_migrator.dart';
import 'serialization.dart';

/// Persistent [ChatLocalDatasource] implementation backed by Hive CE.
///
/// Use the [create] factory to initialize Hive boxes and obtain an instance.
class HiveChatDatasource implements ChatLocalDatasource {
  // === Global box names ===
  //
  // Singleton boxes shared across the entire user session. Keys are
  // entity ids (roomId, userId, etc.); values are JSON-shaped maps.
  static const String _boxMeta = 'chat_meta';
  static const String _boxRooms = 'chat_rooms';
  static const String _boxRoomDetails = 'chat_room_details';
  static const String _boxUsers = 'chat_users';
  static const String _boxContacts = 'chat_contacts';
  static const String _boxUnreads = 'chat_unreads';
  static const String _boxInvited = 'chat_invited';
  static const String _boxOfflineQueue = 'chat_offline_queue';
  static const String _boxPins = 'chat_pins';
  static const String _boxReceipts = 'chat_receipts';

  // === Per-room box prefixes ===
  //
  // One box per room so per-room ops are O(box) instead of O(all
  // messages) and so `clearMessages(roomId)` is a single `.clear()`
  // call. Box name = prefix + `_sanitizeForBoxName(roomId)`.
  static const String _msgBoxPrefix = 'chat_messages_';
  static const String _pendingBoxPrefix = 'chat_pending_';
  static const String _reactionsBoxPrefix = 'chat_reactions_';

  String _messagesBoxName(String roomId) =>
      '$_msgBoxPrefix${_sanitizeForBoxName(roomId)}';
  String _pendingBoxName(String roomId) =>
      '$_pendingBoxPrefix${_sanitizeForBoxName(roomId)}';
  String _reactionsBoxName(String roomId) =>
      '$_reactionsBoxPrefix${_sanitizeForBoxName(roomId)}';

  // === Meta box keys ===
  static const String _messageRoomIdsKey = 'messageRoomIds';
  static const String _schemaVersionKey = 'schemaVersion';
  static const int _schemaVersion = 2;

  late final HiveBoxRegistry _registry;
  late final Box<Map<dynamic, dynamic>> _metaBox;
  final int maxMessagesPerRoom;
  final int? maxRooms;
  final int? maxUsers;
  final int? maxContacts;
  final int? maxOfflineQueueSize;
  final Duration? messageTtl;
  final Duration? messageTtlCheckInterval;
  late final MessageEvictionPolicy _eviction;

  @visibleForTesting
  final Map<int, Future<void> Function()> migrations = {};

  HiveChatDatasource._({
    required this.maxMessagesPerRoom,
    this.maxRooms,
    this.maxUsers,
    this.maxContacts,
    this.maxOfflineQueueSize,
    this.messageTtl,
    this.messageTtlCheckInterval,
    HiveCipher? cipher,
  }) {
    _registry = HiveBoxRegistry(
      cipher: cipher,
      onWarning: (m) => onWarning?.call(m),
      onMetric: (k, d) => onMetric?.call(k, d),
      onBoxRecreated: (name) =>
          _msgIdIndex.invalidateBoxByPrefix(name, _msgBoxPrefix),
    );
    _eviction = MessageEvictionPolicy(
      maxPerRoom: maxMessagesPerRoom,
      ttl: messageTtl,
      checkInterval: messageTtlCheckInterval,
      index: _msgIdIndex,
      safeWrite: _safeWrite,
      onMetric: (k, d) => onMetric?.call(k, d),
    );
  }

  /// Creates and initializes a Hive-backed datasource at the given basePath.
  ///
  /// [encryptionCipher] — optional [HiveCipher] to encrypt all boxes on disk.
  /// The consumer is responsible for generating and securely storing the key
  /// (e.g. via flutter_secure_storage). Passing `null` stores data unencrypted.
  ///
  /// [messageTtl] — when set, messages older than this duration are purged on
  /// startup. Pass `null` (default) to disable automatic expiration.
  ///
  /// [maxRooms] / [maxUsers] — optional limits for cached rooms and users.
  /// When exceeded, the oldest entries are evicted. `null` means unlimited.
  static Future<HiveChatDatasource> create({
    String? basePath,
    int maxMessagesPerRoom = 500,
    int? maxRooms,
    int? maxUsers,
    int? maxContacts,
    int? maxOfflineQueueSize,
    Duration? messageTtl,
    Duration? messageTtlCheckInterval,
    HiveCipher? encryptionCipher,
    @visibleForTesting Map<int, Future<void> Function()>? migrations,
  }) async {
    if (basePath != null) {
      Hive.init(basePath);
    }
    final ds = HiveChatDatasource._(
      maxMessagesPerRoom: maxMessagesPerRoom,
      maxRooms: maxRooms,
      maxUsers: maxUsers,
      maxContacts: maxContacts,
      maxOfflineQueueSize: maxOfflineQueueSize,
      messageTtl: messageTtl,
      messageTtlCheckInterval: messageTtlCheckInterval,
      cipher: encryptionCipher,
    );
    if (migrations != null) ds.migrations.addAll(migrations);
    ds._metaBox = await Hive.openBox<Map<dynamic, dynamic>>(
      _boxMeta,
      encryptionCipher: encryptionCipher,
    );
    await ds._migrateIfNeeded();
    await ds._openCoreBoxes();
    await ds._cleanOrphanedMessageBoxes();
    if (messageTtl != null) {
      await ds._expireOldMessages();
      ds._eviction.startTtlTimer(
        isAlive: () => !ds._isDisposed,
        trigger: ds._expireOldMessages,
      );
    }
    return ds;
  }

  /// Wraps a Hive operation in [ChatResult], converting any exception
  /// thrown by the box op into a [ChatFailureResult]. Logs the error via
  /// [onWarning] so existing observability paths still see it.
  Future<ChatResult<T>> _wrap<T>(Future<T> Function() body) async {
    try {
      final value = await body();
      return ChatSuccess(value);
    } catch (e, st) {
      onWarning?.call('Hive op failed: $e\n$st');
      return ChatFailureResult(UnexpectedFailure(e.toString()));
    }
  }

  Future<void> _cleanOrphanedMessageBoxes() async {
    final trackedRoomIds = _getMessageRoomIds();
    if (trackedRoomIds.isEmpty) return;
    final roomsBox = await _box(_boxRooms);
    final existingRoomIds = roomsBox.keys.cast<String>().toSet();
    final orphans = trackedRoomIds.difference(existingRoomIds);
    for (final roomId in orphans) {
      final name = _messagesBoxName(roomId);
      final box = await _box(name);
      await _safeWrite('cleanOrphans clear', () => box.clear());
      await _registry.deleteFromDisk(name);
    }
    if (orphans.isNotEmpty) {
      final remaining = trackedRoomIds.difference(orphans);
      await _safeWrite(
        'cleanOrphans meta',
        () => _metaBox.put(_messageRoomIdsKey, {'ids': remaining.toList()}),
      );
    }
  }

  Future<void> _migrateIfNeeded() async {
    final migrator = CacheSchemaMigrator(
      metaBox: _metaBox,
      targetVersion: _schemaVersion,
      versionKey: _schemaVersionKey,
      migrations: migrations,
      wipeStrategy: () async {
        await _openCoreBoxes();
        await clear();
      },
      onWarning: (level, message) => onWarning?.call(message),
      onMetric: onMetric,
    );
    await migrator.migrateIfNeeded();
  }

  Future<void> _openCoreBoxes() async {
    await _box(_boxRooms);
    await _box(_boxRoomDetails);
    await _box(_boxUsers);
    await _box(_boxContacts);
    await _box(_boxUnreads);
    await _box(_boxInvited);
    await _box(_boxOfflineQueue);
  }

  // Read defensively — this backs `_cleanOrphanedMessageBoxes()`, called
  // unguarded from `create()` before any box exists yet. A corrupted
  // meta entry (wrong top-level type, or an `ids` list holding
  // non-String elements) must degrade to "no tracked rooms" instead of
  // throwing and crashing app startup.
  Set<String> _getMessageRoomIds() {
    Map<dynamic, dynamic>? data;
    try {
      data = _metaBox.get(_messageRoomIdsKey);
    } catch (_) {
      return {};
    }
    if (data == null) return {};
    final ids = data['ids'];
    if (ids is! List) return {};
    return ids.whereType<String>().toSet();
  }

  Future<void> _trackMessageRoom(String roomId) async {
    final ids = _getMessageRoomIds()..add(roomId);
    await _safeWrite(
      'trackMessageRoom',
      () => _metaBox.put(_messageRoomIdsKey, {'ids': ids.toList()}),
    );
  }

  Future<void> _untrackMessageRoom(String roomId) async {
    final ids = _getMessageRoomIds()..remove(roomId);
    await _safeWrite(
      'untrackMessageRoom',
      () => _metaBox.put(_messageRoomIdsKey, {'ids': ids.toList()}),
    );
  }

  bool _isDisposed = false;

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('HiveChatDatasource is disposed');
  }

  Future<Box<Map<dynamic, dynamic>>> _box(String name) => _registry.box(name);

  Future<void> _safeWrite(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      onWarning?.call('Hive write failed ($operation): $e');
    }
  }

  Future<void> _safeCascade(
    String operation,
    List<Future<void> Function()> steps, {
    Future<void> Function()? onRollback,
  }) async {
    for (var i = 0; i < steps.length; i++) {
      try {
        await steps[i]();
      } catch (e) {
        onWarning?.call('Cascade "$operation" failed at step $i: $e');
        if (onRollback != null) {
          try {
            await onRollback();
          } catch (re) {
            onWarning?.call('Rollback for "$operation" also failed: $re');
          }
        }
        return;
      }
    }
  }

  void Function(String message)? onWarning;
  void Function(String metric, Map<String, dynamic> data)? onMetric;

  List<T> _safeDeserialize<T>(
    Iterable<Map<dynamic, dynamic>> values,
    T Function(Map<String, dynamic>) fromMap, {
    String? boxName,
  }) {
    final result = <T>[];
    final boxSuffix = boxName != null ? ' in $boxName' : '';
    var skipped = 0;
    for (final e in values) {
      try {
        result.add(fromMap(Map<String, dynamic>.from(e)));
      } catch (err) {
        skipped++;
        onWarning?.call('Discarding corrupted record$boxSuffix: $err');
      }
    }
    if (skipped > 0) {
      onWarning?.call('Skipped $skipped corrupted records$boxSuffix');
    }
    return result;
  }

  static String _sanitizeForBoxName(String input) =>
      input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  Future<Box<Map<dynamic, dynamic>>> _messagesBox(String roomId) async {
    final name = _messagesBoxName(roomId);
    await _trackMessageRoom(roomId);
    return _box(name);
  }

  // Messages — keys are `{iso_timestamp}_{msg_id}` for sorted access.
  // Hive returns keys sorted alphabetically = chronologically for ISO 8601.
  // The MessageIdIndex collaborator owns the in-memory `roomId →
  // {msgId → key}` map plus the key-encoding helpers.
  final MessageIdIndex _msgIdIndex = MessageIdIndex();

  // Per-room serialization. saveMessages / updateMessage /
  // deleteMessage / clearMessages all mutate the in-memory
  // _msgIdIndex AND the Hive box, in two separate awaits. Two
  // concurrent ops on the same room would interleave those awaits
  // and leave the index out of sync with the box. The lock chains
  // pending ops onto a single future per room — same-room ops
  // serialize, different-room ops still run in parallel.
  final Map<String, Future<void>> _roomLocks = {};

  Future<T> _withRoomLock<T>(String roomId, Future<T> Function() body) async {
    final previous = _roomLocks[roomId] ?? Future<void>.value();
    final completer = Completer<void>();
    _roomLocks[roomId] = completer.future;
    try {
      await previous;
      return await body();
    } finally {
      completer.complete();
      if (identical(_roomLocks[roomId], completer.future)) {
        _roomLocks.remove(roomId);
      }
    }
  }

  @override
  Future<ChatResult<void>> saveMessages(
    String roomId,
    List<ChatMessage> messages,
  ) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final box = await _messagesBox(roomId);
        final index = _msgIdIndex.getOrBuild(roomId, box);
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
          await _safeWrite(
            'saveMessages dedup',
            () => box.deleteAll(keysToRemove),
          );
        }
        await _safeWrite('saveMessages', () => box.putAll(entries));
        await _eviction.evictIfNeeded(box, roomId: roomId);
      }),
    );
  }

  @override
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
  }) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _messagesBox(roomId);
      var keys = box.keys.cast<String>().toList();

      final clearedAt = (await getClearedAt(roomId)).dataOrNull;
      if (clearedAt != null) {
        // Cutoffs must use the same millisecond-normalized prefix as the
        // keys (MessageIdIndex.keyFor), or a microsecond-precision cursor
        // would mis-compare against truncated keys.
        final cutoff = '${MessageIdIndex.normalizedIso(clearedAt)}_￿';
        keys = keys.where((k) => k.compareTo(cutoff) > 0).toList();
      }

      // Keys are ascending (oldest first) — reverse for newest-first, then take limit.
      final selected = limit != null && keys.length > limit
          ? keys.sublist(keys.length - limit)
          : keys;

      final result = <ChatMessage>[];
      for (final key in selected.reversed) {
        final data = box.get(key);
        if (data == null) continue;
        try {
          result.add(
            messageFromMap(
              Map<String, dynamic>.from(data),
              onWarning: onWarning,
            ),
          );
        } catch (e) {
          onWarning?.call('Skipped corrupted message at key "$key": $e');
        }
      }
      return result;
    });
  }

  @override
  Future<ChatResult<void>> updateMessage(String roomId, ChatMessage message) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final name = _messagesBoxName(roomId);
        final box = await _box(name);
        final key = _msgIdIndex.findKey(roomId, box, message.id);
        if (key != null) {
          await _safeWrite(
            'updateMessage',
            () => box.put(key, messageToMap(message)),
          );
        }
      }),
    );
  }

  @override
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final box = await _messagesBox(roomId);
        final key = _msgIdIndex.findKey(roomId, box, messageId);
        if (key != null) {
          await _safeWrite('deleteMessage', () => box.delete(key));
          _msgIdIndex.removeMessage(roomId, messageId);
        }
      }),
    );
  }

  @override
  Future<ChatResult<void>> clearMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () => _clearMessagesUnlocked(roomId)),
    );
  }

  // Lock-free clear used by cascades (deleteRoom, _evictRoomsIfNeeded)
  // that already hold the room lock. Calling clearMessages from
  // inside the lock would deadlock since _withRoomLock awaits the
  // previous future for the same room — which is the very op
  // running the cascade.
  Future<void> _clearMessagesUnlocked(String roomId) async {
    final name = _messagesBoxName(roomId);
    final box = await _box(name);
    await _safeWrite('clearMessages', () => box.clear());
    _msgIdIndex.invalidateRoom(roomId);
    await _untrackMessageRoom(roomId);
  }

  // Pending/failed outgoing messages — separate box per room. Keyed by
  // message id (not timestamp) so retries can find the entry directly.
  Future<Box<Map<dynamic, dynamic>>> _pendingBox(String roomId) =>
      _box(_pendingBoxName(roomId));

  @override
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      final entry = {'message': messageToMap(message), 'isFailed': isFailed};
      await _safeWrite('savePendingMessage', () => box.put(message.id, entry));
    });
  }

  @override
  Future<ChatResult<List<PendingChatMessage>>> getPendingMessages(
    String roomId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
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
    });
  }

  @override
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      if (box.containsKey(messageId)) {
        await _safeWrite('deletePendingMessage', () => box.delete(messageId));
      }
    });
  }

  @override
  Future<ChatResult<void>> clearPendingMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      await _safeWrite('clearPendingMessages', () => box.clear());
    });
  }

  @override
  Future<ChatResult<void>> setClearedAt(String roomId, DateTime timestamp) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite(
        'setClearedAt',
        () => _metaBox.put('clearedAt_$roomId', {
          'ts': timestamp.toUtc().toIso8601String(),
        }),
      );
    });
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final data = _metaBox.get('clearedAt_$roomId');
      if (data == null) return null;
      final ts = data['ts'] as String?;
      if (ts == null) return null;
      return DateTime.tryParse(ts);
    });
  }

  /// "Delete for me" — persistent per-room set of message IDs the
  /// user wants hidden from their own view. Lives in `_metaBox` next
  /// to `clearedAt_*` so it survives logout/login and app restarts.
  /// The list is filtered post-fetch in `CachedMessagesApi.list`
  /// (incoming network payloads) and applied to the controller after
  /// `messages.load` (defence in depth) — that way a tombstone that
  /// the user dismissed never re-appears just because the next
  /// `GET /rooms/:id/messages` brought it back.
  @override
  Future<ChatResult<void>> hideMessageLocally(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite('hideMessageLocally', () async {
        final key = 'hiddenMessages_$roomId';
        final raw = _metaBox.get(key);
        final ids = <String>{
          ...((raw?['ids'] as List?)?.cast<String>() ?? const <String>[]),
          messageId,
        };
        await _metaBox.put(key, {'ids': ids.toList()});
      });
    });
  }

  @override
  Future<ChatResult<Set<String>>> getHiddenMessageIds(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final data = _metaBox.get('hiddenMessages_$roomId');
      if (data == null) return <String>{};
      final ids = (data['ids'] as List?)?.cast<String>() ?? const <String>[];
      return ids.toSet();
    });
  }

  @override
  Future<ChatResult<void>> clearHiddenMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite(
        'clearHiddenMessages',
        () => _metaBox.delete('hiddenMessages_$roomId'),
      );
    });
  }

  // Rooms

  @override
  Future<ChatResult<void>> saveRooms(List<ChatRoom> rooms) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final room in rooms) {
        entries[room.id] = roomToMap(room);
      }
      await _safeWrite('saveRooms', () => box.putAll(entries));
      await _evictRoomsIfNeeded();
    });
  }

  @override
  Future<ChatResult<List<ChatRoom>>> getRooms() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      return _safeDeserialize(
        box.values,
        (m) => roomFromMap(m, onWarning: onWarning),
        boxName: 'rooms',
      );
    });
  }

  @override
  Future<ChatResult<ChatRoom?>> getRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      final data = box.get(roomId);
      if (data == null) return null;
      try {
        return roomFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final roomsBox = await _box(_boxRooms);
        final detailsBox = await _box(_boxRoomDetails);
        final unreadsBox = await _box(_boxUnreads);
        final invitedBox = await _box(_boxInvited);

        final roomSnapshot = roomsBox.get(roomId);
        final detailSnapshot = detailsBox.get(roomId);
        final unreadSnapshot = unreadsBox.get(roomId);
        final invitedSnapshot = <dynamic, Map<dynamic, dynamic>>{};
        for (final entry in invitedBox.toMap().entries) {
          final map = Map<String, dynamic>.from(entry.value);
          if (map['roomId'] == roomId) {
            invitedSnapshot[entry.key] = entry.value;
          }
        }

        await _safeCascade(
          'deleteRoom($roomId)',
          [
            () async => roomsBox.delete(roomId),
            () async => detailsBox.delete(roomId),
            () async => _clearMessagesUnlocked(roomId),
            () async => unreadsBox.delete(roomId),
            () async {
              for (final key in invitedSnapshot.keys) {
                await invitedBox.delete(key);
              }
            },
            () async {
              final reactionsBox = await _box(_reactionsBoxName(roomId));
              await reactionsBox.clear();
            },
            () async {
              final pinsBox = await _box(_boxPins);
              await pinsBox.delete(roomId);
            },
            () async {
              final receiptsBox = await _box(_boxReceipts);
              await receiptsBox.delete(roomId);
            },
            () async => clearPendingMessages(roomId),
            // NOTE: the `clearedAt_$roomId` cutoff is deliberately NOT
            // deleted here. It is a never-evictable per-user marker (twin
            // of `deletedRoomIds`): a deleted chat keeps its cutoff so it
            // reappears EMPTY (not repopulated) if a peer writes again.
          ],
          onRollback: () async {
            if (roomSnapshot != null) {
              await roomsBox.put(roomId, roomSnapshot);
            }
            if (detailSnapshot != null) {
              await detailsBox.put(roomId, detailSnapshot);
            }
            if (unreadSnapshot != null) {
              await unreadsBox.put(roomId, unreadSnapshot);
            }
            for (final entry in invitedSnapshot.entries) {
              await invitedBox.put(entry.key, entry.value);
            }
          },
        );
      }),
    );
  }

  // Room details

  @override
  Future<ChatResult<void>> saveRoomDetail(RoomDetail detail) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      await _safeWrite(
        'saveRoomDetail',
        () => box.put(detail.id, roomDetailToMap(detail)),
      );
    });
  }

  @override
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      final data = box.get(roomId);
      if (data == null) return null;
      try {
        return roomDetailFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteRoomDetail(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      await _safeWrite('deleteRoomDetail', () => box.delete(roomId));
    });
  }

  // Users

  @override
  Future<ChatResult<void>> saveUsers(List<ChatUser> users) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final user in users) {
        entries[user.id] = userToMap(user);
      }
      await _safeWrite('saveUsers', () => box.putAll(entries));
      await _evictUsersIfNeeded();
    });
  }

  @override
  Future<ChatResult<List<ChatUser>>> getUsers() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      return _safeDeserialize(
        box.values,
        (m) => userFromMap(m, onWarning: onWarning),
        boxName: 'users',
      );
    });
  }

  @override
  Future<ChatResult<ChatUser?>> getUser(String userId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      final data = box.get(userId);
      if (data == null) return null;
      try {
        return userFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteUser(String userId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      await _safeWrite('deleteUser', () => box.delete(userId));
    });
  }

  // Contacts

  @override
  Future<ChatResult<void>> saveContacts(List<ChatContact> contacts) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxContacts);
      await _safeWrite('saveContacts clear', () => box.clear());
      final limited = maxContacts != null && contacts.length > maxContacts!
          ? contacts.sublist(0, maxContacts!)
          : contacts;
      final entries = <int, Map<dynamic, dynamic>>{};
      for (var i = 0; i < limited.length; i++) {
        entries[i] = contactToMap(limited[i]);
      }
      await _safeWrite('saveContacts putAll', () => box.putAll(entries));
      if (maxContacts != null && contacts.length > maxContacts!) {
        onMetric?.call('cache_eviction', {
          'entity': 'contacts',
          'count': contacts.length - maxContacts!,
        });
      }
    });
  }

  @override
  Future<ChatResult<List<ChatContact>>> getContacts() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxContacts);
      return _safeDeserialize(box.values, contactFromMap, boxName: 'contacts');
    });
  }

  // Unreads

  @override
  Future<ChatResult<void>> saveUnreads(List<UnreadRoom> unreads) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final u in unreads) {
        entries[u.roomId] = unreadRoomToMap(u);
      }
      await _safeWrite('saveUnreads', () => box.putAll(entries));
    });
  }

  @override
  Future<ChatResult<void>> reconcileUnreads(List<UnreadRoom> unreads) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      final serverIds = unreads.map((u) => u.roomId).toSet();
      final kicked = _readKickedRoomIds();
      final stale = box.keys
          .map((k) => k.toString())
          .where((id) => !serverIds.contains(id) && !kicked.contains(id))
          .toList();
      await _safeWrite('reconcileUnreads evict', () async {
        for (final id in stale) {
          await box.delete(id);
        }
      });
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final u in unreads) {
        entries[u.roomId] = unreadRoomToMap(u);
      }
      await _safeWrite('reconcileUnreads putAll', () => box.putAll(entries));
    });
  }

  @override
  Future<ChatResult<List<UnreadRoom>>> getUnreads() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      return _safeDeserialize(
        box.values,
        (m) => unreadRoomFromMap(m, onWarning: onWarning),
        boxName: 'unreads',
      );
    });
  }

  // Invited rooms

  @override
  Future<ChatResult<void>> saveInvitedRooms(List<InvitedRoom> invitedRooms) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxInvited);
      await _safeWrite('saveInvitedRooms clear', () => box.clear());
      final entries = <int, Map<dynamic, dynamic>>{};
      for (var i = 0; i < invitedRooms.length; i++) {
        entries[i] = invitedRoomToMap(invitedRooms[i]);
      }
      await _safeWrite('saveInvitedRooms putAll', () => box.putAll(entries));
    });
  }

  @override
  Future<ChatResult<List<InvitedRoom>>> getInvitedRooms() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxInvited);
      return _safeDeserialize(
        box.values,
        invitedRoomFromMap,
        boxName: 'invited',
      );
    });
  }

  // Unreads (individual)

  @override
  Future<ChatResult<void>> deleteUnread(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      await _safeWrite('deleteUnread', () => box.delete(roomId));
    });
  }

  // Offline queue
  //
  // Unlike per-room message boxes (guarded by `_withRoomLock`), the
  // offline queue is a single global box mutated with a two-step
  // "putAll then trim" sequence in `saveOfflineQueue`. `OfflineQueue`
  // fire-and-forgets `_persist()` on every `enqueue()`, so two calls in
  // quick succession (e.g. the user queuing several offline attachments
  // back to back) dispatch two overlapping `saveOfflineQueue` futures.
  // Hive applies each `putAll`/`deleteAll` to the box's in-memory
  // keystore synchronously as soon as it starts (before awaiting the
  // disk flush), so the second call's `putAll` becomes visible to the
  // FIRST call's `box.keys` read the moment it runs — the first call
  // then computes its trim range against a box that already contains
  // the second call's freshly-added keys and deletes them, silently
  // truncating the persisted queue below what's actually enqueued.
  // `_offlineQueueLockKey` serializes every mutation through the same
  // per-key chain used for rooms so overlapping saves/clears run one
  // at a time instead of interleaving.
  static const _offlineQueueLockKey = ' offline_queue';

  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(_offlineQueueLockKey, () async {
        final box = await _box(_boxOfflineQueue);
        final limited =
            maxOfflineQueueSize != null &&
                operations.length > maxOfflineQueueSize!
            ? operations.sublist(operations.length - maxOfflineQueueSize!)
            : operations;
        final entries = <int, Map<dynamic, dynamic>>{};
        for (var i = 0; i < limited.length; i++) {
          entries[i] = limited[i];
        }
        await _safeWrite('saveOfflineQueue putAll', () => box.putAll(entries));
        final keysToRemove = box.keys
            .where((k) => k is int && k >= limited.length)
            .toList();
        if (keysToRemove.isNotEmpty) {
          await _safeWrite(
            'saveOfflineQueue trim',
            () => box.deleteAll(keysToRemove),
          );
        }
        if (maxOfflineQueueSize != null &&
            operations.length > maxOfflineQueueSize!) {
          onMetric?.call('cache_eviction', {
            'entity': 'offlineQueue',
            'count': operations.length - maxOfflineQueueSize!,
          });
        }
      }),
    );
  }

  @override
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxOfflineQueue);
      return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
    });
  }

  @override
  Future<ChatResult<void>> clearOfflineQueue() {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(_offlineQueueLockKey, () async {
        final box = await _box(_boxOfflineQueue);
        await _safeWrite('clearOfflineQueue', () => box.clear());
      }),
    );
  }

  // Kicked-rooms registry — see [ChatLocalDatasource.markKicked].
  // Stored in `_metaBox` (the same scratch box used for
  // `messageRoomIds`, `schemaVersion`, etc.) under the key
  // `kickedRoomIds`. Persists across cold starts so a user kicked
  // from a group keeps the chat visible (read-only) after a
  // restart — WhatsApp-parity. Cleared on admin re-add via
  // `unmarkKicked` or by an explicit
  // `ChatRoomOption.deleteKickedChat` tap from the room options
  // menu (host wires that to `unmarkKicked` + `hideRoom`).
  static const _kickedRoomIdsKey = 'kickedRoomIds';

  Set<String> _readKickedRoomIds() {
    final data = _metaBox.get(_kickedRoomIdsKey);
    if (data == null) return <String>{};
    final ids = data['ids'];
    if (ids is List) return ids.cast<String>().toSet();
    return <String>{};
  }

  @override
  Future<ChatResult<void>> markKicked(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readKickedRoomIds()..add(roomId);
      await _safeWrite(
        'markKicked',
        () => _metaBox.put(_kickedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<void>> unmarkKicked(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readKickedRoomIds();
      if (!ids.remove(roomId)) return;
      await _safeWrite(
        'unmarkKicked',
        () => _metaBox.put(_kickedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<Set<String>>> getKickedRoomIds() {
    _checkNotDisposed();
    return _wrap(() async => _readKickedRoomIds());
  }

  // Deleted-rooms registry — see [ChatLocalDatasource.addDeletedRoom].
  // Stored in `_metaBox` under `deletedRoomIds`. Deliberately
  // NEVER-EVICTABLE: `deleteRoom`'s cascade and `_evictRoomsIfNeeded`
  // both leave this key (and the matching `clearedAt_*` cutoff)
  // untouched, so a chat the user deleted does not silently reappear
  // after room/message eviction. Cleared only by `clearDeletedRoom`
  // (peer writes again / unarchive) or a full `clear()` (logout).
  static const _deletedRoomIdsKey = 'deletedRoomIds';

  Set<String> _readDeletedRoomIds() {
    final data = _metaBox.get(_deletedRoomIdsKey);
    if (data == null) return <String>{};
    final ids = data['ids'];
    if (ids is List) return ids.cast<String>().toSet();
    return <String>{};
  }

  @override
  Future<ChatResult<void>> addDeletedRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readDeletedRoomIds()..add(roomId);
      await _safeWrite(
        'addDeletedRoom',
        () => _metaBox.put(_deletedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<void>> clearDeletedRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readDeletedRoomIds();
      if (!ids.remove(roomId)) return;
      await _safeWrite(
        'clearDeletedRoom',
        () => _metaBox.put(_deletedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() {
    _checkNotDisposed();
    return _wrap(() async => _readDeletedRoomIds());
  }

  // Reactions

  @override
  Future<ChatResult<void>> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      await _safeWrite(
        'saveReactions',
        () => box.put(messageId, {
          'items': reactions.map(reactionToMap).toList(),
        }),
      );
    });
  }

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      final raw = box.get(messageId);
      if (raw == null) return <AggregatedReaction>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(
        items,
        (m) => reactionFromMap(m),
        boxName: 'reactions',
      );
    });
  }

  @override
  Future<ChatResult<void>> deleteReactions(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      await _safeWrite('deleteReactions', () => box.delete(messageId));
    });
  }

  // Pins

  @override
  Future<ChatResult<void>> savePins(String roomId, List<MessagePin> pins) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      await _safeWrite(
        'savePins',
        () => box.put(roomId, {'items': pins.map(pinToMap).toList()}),
      );
    });
  }

  @override
  Future<ChatResult<List<MessagePin>>> getPins(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      final raw = box.get(roomId);
      if (raw == null) return <MessagePin>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(items, (m) => pinFromMap(m), boxName: 'pins');
    });
  }

  @override
  Future<ChatResult<void>> deletePin(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      final raw = box.get(roomId);
      if (raw == null) return;
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      final filtered = items
          .where((m) => Map<String, dynamic>.from(m)['messageId'] != messageId)
          .toList();
      await _safeWrite('deletePin', () => box.put(roomId, {'items': filtered}));
    });
  }

  // Read receipts

  @override
  Future<ChatResult<void>> saveReceipts(
    String roomId,
    List<ReadReceipt> receipts,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxReceipts);
      await _safeWrite(
        'saveReceipts',
        () => box.put(roomId, {'items': receipts.map(receiptToMap).toList()}),
      );
    });
  }

  @override
  Future<ChatResult<List<ReadReceipt>>> getReceipts(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxReceipts);
      final raw = box.get(roomId);
      if (raw == null) return <ReadReceipt>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(
        items,
        (m) => receiptFromMap(m),
        boxName: 'receipts',
      );
    });
  }

  // TTL expiration — delegates to the eviction policy. Kept as a
  // private method so the create() factory can call it inline.
  Future<void> _expireOldMessages() => _eviction.expireOldMessages(
    trackedRoomIds: _getMessageRoomIds(),
    boxFor: (roomId) => _box(_messagesBoxName(roomId)),
  );

  // Entity eviction

  Future<void> _evictRoomsIfNeeded() async {
    if (maxRooms == null) return;
    final box = await _box(_boxRooms);
    if (box.length <= maxRooms!) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxRooms!);
    await _safeWrite('evictRooms', () => box.deleteAll(toRemove));
    // Cascade: clean orphaned data for evicted rooms (best-effort, no rollback)
    final detailsBox = await _box(_boxRoomDetails);
    final unreadsBox = await _box(_boxUnreads);
    final invitedBox = await _box(_boxInvited);
    final pinsBox = await _box(_boxPins);
    final receiptsBox = await _box(_boxReceipts);
    for (final roomId in toRemove) {
      await _withRoomLock(roomId, () async {
        await _safeWrite('evictRooms details', () => detailsBox.delete(roomId));
        await _safeWrite('evictRooms unreads', () => unreadsBox.delete(roomId));
        await _clearMessagesUnlocked(roomId);
        final reactionsBox = await _box(_reactionsBoxName(roomId));
        await _safeWrite('evictRooms reactions', () => reactionsBox.clear());
        await _safeWrite('evictRooms pins', () => pinsBox.delete(roomId));
        await _safeWrite(
          'evictRooms receipts',
          () => receiptsBox.delete(roomId),
        );
        // The `clearedAt_$roomId` cutoff is intentionally preserved
        // across eviction (never-evictable per-user marker, twin of
        // `deletedRoomIds`) so a deleted chat reappears EMPTY rather
        // than repopulated if the room is re-fetched later.
        await clearPendingMessages(roomId);
      });
    }
    // Remove invited entries for evicted rooms
    final invitedEntries = invitedBox.toMap().entries.where((e) {
      final map = Map<String, dynamic>.from(e.value);
      return toRemove.contains(map['roomId']);
    }).toList();
    for (final entry in invitedEntries) {
      await _safeWrite(
        'evictRooms invited',
        () => invitedBox.delete(entry.key),
      );
    }
    onMetric?.call('cache_eviction', {
      'entity': 'rooms',
      'count': toRemove.length,
    });
  }

  Future<void> _evictUsersIfNeeded() async {
    if (maxUsers == null) return;
    final box = await _box(_boxUsers);
    if (box.length <= maxUsers!) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxUsers!);
    await _safeWrite('evictUsers', () => box.deleteAll(toRemove));
    onMetric?.call('cache_eviction', {
      'entity': 'users',
      'count': toRemove.length,
    });
  }

  // Backup / restore

  Future<Map<String, dynamic>> exportData() async {
    _checkNotDisposed();
    final roomsBox = await _box(_boxRooms);
    final detailsBox = await _box(_boxRoomDetails);
    final usersBox = await _box(_boxUsers);
    final contactsBox = await _box(_boxContacts);
    final unreadsBox = await _box(_boxUnreads);
    final invitedBox = await _box(_boxInvited);

    final rooms = roomsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final roomDetails = detailsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final users = usersBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final contacts = contactsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final unreads = unreadsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final invitedRooms = invitedBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return {
      'version': _schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'validation': {
        'roomCount': rooms.length,
        'roomDetailCount': roomDetails.length,
        'userCount': users.length,
        'contactCount': contacts.length,
        'unreadCount': unreads.length,
        'invitedRoomCount': invitedRooms.length,
      },
      'rooms': rooms,
      'roomDetails': roomDetails,
      'users': users,
      'contacts': contacts,
      'unreads': unreads,
      'invitedRooms': invitedRooms,
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    _checkNotDisposed();
    final version = data['version'] as int?;
    if (version != _schemaVersion) {
      throw ArgumentError(
        'Incompatible schema version: expected $_schemaVersion, got $version',
      );
    }

    final validation = data['validation'] as Map<String, dynamic>?;
    final rooms = (data['rooms'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final roomDetails =
        (data['roomDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final users = (data['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final contacts =
        (data['contacts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final unreads =
        (data['unreads'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final invitedRooms =
        (data['invitedRooms'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (validation != null) {
      final mismatches = <String>[];
      void check(String key, int actual) {
        final expected = validation[key] as int?;
        if (expected != null && expected != actual) {
          mismatches.add('$key: expected $expected, got $actual');
        }
      }

      check('roomCount', rooms.length);
      check('roomDetailCount', roomDetails.length);
      check('userCount', users.length);
      check('contactCount', contacts.length);
      check('unreadCount', unreads.length);
      check('invitedRoomCount', invitedRooms.length);
      if (mismatches.isNotEmpty) {
        onWarning?.call('Import validation mismatch: ${mismatches.join(', ')}');
      }
    }

    final roomsBox = await _box(_boxRooms);
    final detailsBox = await _box(_boxRoomDetails);
    final usersBox = await _box(_boxUsers);
    final contactsBox = await _box(_boxContacts);
    final unreadsBox = await _box(_boxUnreads);
    final invitedBox = await _box(_boxInvited);

    await _safeWrite('importData clear rooms', () => roomsBox.clear());
    await _safeWrite('importData clear details', () => detailsBox.clear());
    await _safeWrite('importData clear users', () => usersBox.clear());
    await _safeWrite('importData clear contacts', () => contactsBox.clear());
    await _safeWrite('importData clear unreads', () => unreadsBox.clear());
    await _safeWrite('importData clear invited', () => invitedBox.clear());

    for (final room in rooms) {
      final id = room['id'] as String?;
      if (id != null) {
        await _safeWrite('importData room', () => roomsBox.put(id, room));
      }
    }
    for (final detail in roomDetails) {
      final id = detail['id'] as String?;
      if (id != null) {
        await _safeWrite('importData detail', () => detailsBox.put(id, detail));
      }
    }
    for (final user in users) {
      final id = user['id'] as String?;
      if (id != null) {
        await _safeWrite('importData user', () => usersBox.put(id, user));
      }
    }
    for (var i = 0; i < contacts.length; i++) {
      await _safeWrite(
        'importData contact',
        () => contactsBox.put(i, contacts[i]),
      );
    }
    for (final unread in unreads) {
      final roomId = unread['roomId'] as String?;
      if (roomId != null) {
        await _safeWrite(
          'importData unread',
          () => unreadsBox.put(roomId, unread),
        );
      }
    }
    for (var i = 0; i < invitedRooms.length; i++) {
      await _safeWrite(
        'importData invited',
        () => invitedBox.put(i, invitedRooms[i]),
      );
    }
  }

  // Cache manager TTL timestamps. See [ChatLocalDatasource.loadCacheTimestamps].
  static const _cacheManagerTimestampsKey = 'cacheManagerTimestamps';

  @override
  Future<Map<String, DateTime>> loadCacheTimestamps() async {
    _checkNotDisposed();
    final data = _metaBox.get(_cacheManagerTimestampsKey);
    if (data == null) return const <String, DateTime>{};
    final result = <String, DateTime>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is int) {
        result[key] = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
    }
    return result;
  }

  @override
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {
    _checkNotDisposed();
    final payload = <String, int>{
      for (final entry in timestamps.entries)
        entry.key: entry.value.toUtc().millisecondsSinceEpoch,
    };
    await _safeWrite(
      'saveCacheTimestamps',
      () => _metaBox.put(_cacheManagerTimestampsKey, payload),
    );
  }

  // Lifecycle

  @override
  Future<ChatResult<void>> clear() {
    return _wrap(() async {
      await _registry.clearAll();
      // Delete message boxes that aren't open from disk
      for (final roomId in _getMessageRoomIds()) {
        final name = _messagesBoxName(roomId);
        if (!_registry.isTracked(name)) {
          try {
            await Hive.deleteBoxFromDisk(name);
          } catch (_) {}
        }
      }
      _msgIdIndex.clear();
      if (_metaBox.isOpen) {
        await _safeWrite('clear metaBox', () => _metaBox.clear());
      }
    });
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _eviction.stopTtlTimer();
    await _registry.closeAll();
    if (_metaBox.isOpen) await _metaBox.close();
  }
}
