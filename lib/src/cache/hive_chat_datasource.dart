import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:flutter/foundation.dart';
import 'package:noma_chat/noma_chat.dart';

import 'serialization.dart';

/// Persistent [ChatLocalDatasource] implementation backed by Hive CE.
///
/// Use the [create] factory to initialize Hive boxes and obtain an instance.
class HiveChatDatasource implements ChatLocalDatasource {
  static const _messageRoomIdsKey = 'messageRoomIds';
  static const _schemaVersionKey = 'schemaVersion';
  static const _schemaVersion = 2;

  final Map<String, Box<Map<dynamic, dynamic>>> _openBoxes = {};
  final Map<String, Future<Box<Map<dynamic, dynamic>>>> _pendingOpens = {};
  late final Box<Map<dynamic, dynamic>> _metaBox;
  final int maxMessagesPerRoom;
  final int? maxRooms;
  final int? maxUsers;
  final int? maxContacts;
  final int? maxOfflineQueueSize;
  final Duration? messageTtl;
  final Duration? messageTtlCheckInterval;
  final HiveCipher? _cipher;
  Timer? _ttlTimer;

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
  }) : _cipher = cipher;

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
      'chat_meta',
      encryptionCipher: encryptionCipher,
    );
    await ds._migrateIfNeeded();
    await ds._openCoreBoxes();
    await ds._cleanOrphanedMessageBoxes();
    if (messageTtl != null) {
      await ds._expireOldMessages();
      if (messageTtlCheckInterval != null) {
        ds._ttlTimer = Timer.periodic(messageTtlCheckInterval, (_) {
          if (!ds._isDisposed) ds._expireOldMessages();
        });
      }
    }
    return ds;
  }

  Future<void> _cleanOrphanedMessageBoxes() async {
    final trackedRoomIds = _getMessageRoomIds();
    if (trackedRoomIds.isEmpty) return;
    final roomsBox = await _box('chat_rooms');
    final existingRoomIds = roomsBox.keys.cast<String>().toSet();
    final orphans = trackedRoomIds.difference(existingRoomIds);
    for (final roomId in orphans) {
      final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
      final box = await _box(name);
      await _safeWrite('cleanOrphans clear', () => box.clear());
      await box.close();
      _openBoxes.remove(name);
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (e) {
        onWarning?.call('Failed to delete orphan box "$name": $e');
      }
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
    final stored = _metaBox.get(_schemaVersionKey);
    final storedVersion = (stored?['version'] as int?) ?? 0;
    if (storedVersion == _schemaVersion) return;

    if (storedVersion < _schemaVersion) {
      var v = storedVersion;
      while (v < _schemaVersion) {
        final nextVersion = v + 1;
        final migration = migrations[nextVersion];
        if (migration != null) {
          await migration();
        } else {
          onWarning?.call(
            'Schema migration: no migration from v$storedVersion to v$_schemaVersion, wiping cache',
          );
          onMetric?.call('schema_migration_wipe', {
            'from': storedVersion,
            'to': _schemaVersion,
            'reason': 'no_migration_path',
          });
          await _openCoreBoxes();
          await clear();
          break;
        }
        v = nextVersion;
      }
    } else {
      onWarning?.call(
        'Schema migration: downgrade from v$storedVersion to v$_schemaVersion, wiping cache',
      );
      onMetric?.call('schema_migration_wipe', {
        'from': storedVersion,
        'to': _schemaVersion,
        'reason': 'downgrade',
      });
      await _openCoreBoxes();
      await clear();
    }

    await _safeWrite(
      'migrateIfNeeded',
      () => _metaBox.put(_schemaVersionKey, {'version': _schemaVersion}),
    );
  }

  Future<void> _openCoreBoxes() async {
    await _box('chat_rooms');
    await _box('chat_room_details');
    await _box('chat_users');
    await _box('chat_contacts');
    await _box('chat_unreads');
    await _box('chat_invited');
    await _box('chat_offline_queue');
  }

  Set<String> _getMessageRoomIds() {
    final data = _metaBox.get(_messageRoomIdsKey);
    if (data == null) return {};
    return (data['ids'] as List?)?.cast<String>().toSet() ?? {};
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

  Future<Box<Map<dynamic, dynamic>>> _box(String name) async {
    final cached = _openBoxes[name];
    if (cached != null && cached.isOpen) return cached;
    if (_pendingOpens.containsKey(name)) {
      return _pendingOpens[name]!;
    }
    final future = _openBoxSafe(name);
    _pendingOpens[name] = future;
    return future;
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
      onWarning?.call('Box "$name" corrupted, deleting and recreating: $e');
      onMetric?.call('box_corrupted', {'box': name, 'error': '$e'});
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteErr) {
        onWarning?.call('Failed to delete corrupted box "$name": $deleteErr');
        onMetric?.call('box_delete_failed', {
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
        _clearMsgIdIndexForBox(name);
        return box;
      } catch (e2) {
        onWarning?.call('Failed to reopen box "$name" after recreation: $e2');
        onMetric?.call('box_reopen_failed', {'box': name, 'error': '$e2'});
        _pendingOpens.remove(name);
        rethrow;
      }
    }
  }

  void _clearMsgIdIndexForBox(String boxName) {
    const prefix = 'chat_messages_';
    if (boxName.startsWith(prefix)) {
      final roomId = boxName.substring(prefix.length);
      _msgIdIndex.remove(roomId);
    }
  }

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
    var skipped = 0;
    Object? firstError;
    for (final e in values) {
      try {
        result.add(fromMap(Map<String, dynamic>.from(e)));
      } catch (err) {
        skipped++;
        firstError ??= err;
      }
    }
    if (skipped > 0) {
      final boxSuffix = boxName != null ? ' in $boxName' : '';
      final errorSuffix = firstError != null
          ? ' (first error: $firstError)'
          : '';
      onWarning?.call(
        'Skipped $skipped corrupted records$boxSuffix$errorSuffix',
      );
    }
    return result;
  }

  static String _sanitizeForBoxName(String input) =>
      input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  Future<Box<Map<dynamic, dynamic>>> _messagesBox(String roomId) async {
    final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
    await _trackMessageRoom(roomId);
    return _box(name);
  }

  // Messages — keys are `{iso_timestamp}_{msg_id}` for sorted access.
  // Hive returns keys sorted alphabetically = chronologically for ISO 8601.
  // In-memory index: roomId -> {msgId -> timestampKey} for O(1) lookup.
  final Map<String, Map<String, String>> _msgIdIndex = {};

  static String _messageKey(DateTime timestamp, String id) =>
      '${timestamp.toUtc().toIso8601String()}_$id';

  static String? _extractMsgId(String key) {
    final idx = key.indexOf('_');
    return idx >= 0 ? key.substring(idx + 1) : null;
  }

  Map<String, String> _getOrBuildIndex(
    String roomId,
    Box<Map<dynamic, dynamic>> box,
  ) {
    if (_msgIdIndex.containsKey(roomId)) return _msgIdIndex[roomId]!;
    final index = <String, String>{};
    for (final key in box.keys.cast<String>()) {
      final msgId = _extractMsgId(key);
      if (msgId != null) index[msgId] = key;
    }
    _msgIdIndex[roomId] = index;
    return index;
  }

  String? _findKeyByMessageId(
    String roomId,
    Box<Map<dynamic, dynamic>> box,
    String messageId,
  ) {
    return _getOrBuildIndex(roomId, box)[messageId];
  }

  @override
  Future<void> saveMessages(String roomId, List<ChatMessage> messages) async {
    _checkNotDisposed();
    final box = await _messagesBox(roomId);
    final index = _getOrBuildIndex(roomId, box);
    final entries = <String, Map<dynamic, dynamic>>{};
    final keysToRemove = <String>[];
    for (final msg in messages) {
      final newKey = _messageKey(msg.timestamp, msg.id);
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
    await _evictOldMessages(box, roomId: roomId);
  }

  Future<void> _evictOldMessages(
    Box<Map<dynamic, dynamic>> box, {
    String? roomId,
  }) async {
    if (box.length <= maxMessagesPerRoom) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxMessagesPerRoom);
    await _safeWrite('evictOldMessages', () => box.deleteAll(toRemove));
    if (roomId != null) {
      final index = _msgIdIndex[roomId];
      if (index != null) {
        for (final key in toRemove) {
          final msgId = _extractMsgId(key);
          if (msgId != null) index.remove(msgId);
        }
      }
    }
    onMetric?.call('cache_eviction', {
      'entity': 'messages',
      'count': toRemove.length,
    });
  }

  @override
  Future<List<ChatMessage>> getMessages(
    String roomId, {
    int? limit,
    String? before,
    String? after,
  }) async {
    _checkNotDisposed();
    final box = await _messagesBox(roomId);
    var keys = box.keys.cast<String>().toList();

    final clearedAt = await getClearedAt(roomId);
    if (clearedAt != null) {
      final cutoff = '${clearedAt.toUtc().toIso8601String()}_\uffff';
      keys = keys.where((k) => k.compareTo(cutoff) > 0).toList();
    }

    if (before != null) {
      final beforeTime = DateTime.tryParse(before);
      if (beforeTime == null) {
        onWarning?.call('Invalid before cursor (not a timestamp): $before');
        return [];
      }
      final cutoffPrefix = beforeTime.toUtc().toIso8601String();
      keys = keys.where((k) => k.compareTo(cutoffPrefix) < 0).toList();
    }

    if (after != null) {
      final afterTime = DateTime.tryParse(after);
      if (afterTime == null) {
        onWarning?.call('Invalid after cursor (not a timestamp): $after');
        return [];
      }
      // Pad with suffix to exclude keys at the exact timestamp (keys are {ts}_{id}).
      final cutoff = '${afterTime.toUtc().toIso8601String()}_\uffff';
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
          messageFromMap(Map<String, dynamic>.from(data), onWarning: onWarning),
        );
      } catch (e) {
        onWarning?.call('Skipped corrupted message at key "$key": $e');
      }
    }
    return result;
  }

  @override
  Future<void> updateMessage(String roomId, ChatMessage message) async {
    _checkNotDisposed();
    final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
    final box = await _box(name);
    final key = _findKeyByMessageId(roomId, box, message.id);
    if (key != null) {
      await _safeWrite(
        'updateMessage',
        () => box.put(key, messageToMap(message)),
      );
    }
  }

  @override
  Future<void> deleteMessage(String roomId, String messageId) async {
    _checkNotDisposed();
    final box = await _messagesBox(roomId);
    final key = _findKeyByMessageId(roomId, box, messageId);
    if (key != null) {
      await _safeWrite('deleteMessage', () => box.delete(key));
      _msgIdIndex[roomId]?.remove(messageId);
    }
  }

  @override
  Future<void> clearMessages(String roomId) async {
    _checkNotDisposed();
    final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
    final box = await _box(name);
    await _safeWrite('clearMessages', () => box.clear());
    _msgIdIndex.remove(roomId);
    await _untrackMessageRoom(roomId);
  }

  // Pending/failed outgoing messages — separate box per room. Keyed by
  // message id (not timestamp) so retries can find the entry directly.
  Future<Box<Map<dynamic, dynamic>>> _pendingBox(String roomId) =>
      _box('chat_pending_${_sanitizeForBoxName(roomId)}');

  @override
  Future<void> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async {
    _checkNotDisposed();
    final box = await _pendingBox(roomId);
    final entry = {'message': messageToMap(message), 'isFailed': isFailed};
    await _safeWrite('savePendingMessage', () => box.put(message.id, entry));
  }

  @override
  Future<List<PendingChatMessage>> getPendingMessages(String roomId) async {
    _checkNotDisposed();
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
  }

  @override
  Future<void> deletePendingMessage(String roomId, String messageId) async {
    _checkNotDisposed();
    final box = await _pendingBox(roomId);
    if (box.containsKey(messageId)) {
      await _safeWrite('deletePendingMessage', () => box.delete(messageId));
    }
  }

  @override
  Future<void> clearPendingMessages(String roomId) async {
    _checkNotDisposed();
    final box = await _pendingBox(roomId);
    await _safeWrite('clearPendingMessages', () => box.clear());
  }

  @override
  Future<void> setClearedAt(String roomId, DateTime timestamp) async {
    _checkNotDisposed();
    await _safeWrite(
      'setClearedAt',
      () => _metaBox.put('clearedAt_$roomId', {
        'ts': timestamp.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<DateTime?> getClearedAt(String roomId) async {
    _checkNotDisposed();
    final data = _metaBox.get('clearedAt_$roomId');
    if (data == null) return null;
    final ts = data['ts'] as String?;
    if (ts == null) return null;
    return DateTime.tryParse(ts);
  }

  // Rooms

  @override
  Future<void> saveRooms(List<ChatRoom> rooms) async {
    _checkNotDisposed();
    final box = await _box('chat_rooms');
    final entries = <String, Map<dynamic, dynamic>>{};
    for (final room in rooms) {
      entries[room.id] = roomToMap(room);
    }
    await _safeWrite('saveRooms', () => box.putAll(entries));
    await _evictRoomsIfNeeded();
  }

  @override
  Future<List<ChatRoom>> getRooms() async {
    _checkNotDisposed();
    final box = await _box('chat_rooms');
    return _safeDeserialize(
      box.values,
      (m) => roomFromMap(m, onWarning: onWarning),
      boxName: 'rooms',
    );
  }

  @override
  Future<ChatRoom?> getRoom(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_rooms');
    final data = box.get(roomId);
    if (data == null) return null;
    try {
      return roomFromMap(Map<String, dynamic>.from(data), onWarning: onWarning);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    _checkNotDisposed();
    final roomsBox = await _box('chat_rooms');
    final detailsBox = await _box('chat_room_details');
    final unreadsBox = await _box('chat_unreads');
    final invitedBox = await _box('chat_invited');

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
        () async => clearMessages(roomId),
        () async => unreadsBox.delete(roomId),
        () async {
          for (final key in invitedSnapshot.keys) {
            await invitedBox.delete(key);
          }
        },
        () async {
          final reactionsBox = await _box(
            'chat_reactions_${_sanitizeForBoxName(roomId)}',
          );
          await reactionsBox.clear();
        },
        () async {
          final pinsBox = await _box('chat_pins');
          await pinsBox.delete(roomId);
        },
        () async {
          final receiptsBox = await _box('chat_receipts');
          await receiptsBox.delete(roomId);
        },
        () async => clearPendingMessages(roomId),
        () async => _metaBox.delete('clearedAt_$roomId'),
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
  }

  // Room details

  @override
  Future<void> saveRoomDetail(RoomDetail detail) async {
    _checkNotDisposed();
    final box = await _box('chat_room_details');
    await _safeWrite(
      'saveRoomDetail',
      () => box.put(detail.id, roomDetailToMap(detail)),
    );
  }

  @override
  Future<RoomDetail?> getRoomDetail(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_room_details');
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
  }

  @override
  Future<void> deleteRoomDetail(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_room_details');
    await _safeWrite('deleteRoomDetail', () => box.delete(roomId));
  }

  // Users

  @override
  Future<void> saveUsers(List<ChatUser> users) async {
    _checkNotDisposed();
    final box = await _box('chat_users');
    final entries = <String, Map<dynamic, dynamic>>{};
    for (final user in users) {
      entries[user.id] = userToMap(user);
    }
    await _safeWrite('saveUsers', () => box.putAll(entries));
    await _evictUsersIfNeeded();
  }

  @override
  Future<List<ChatUser>> getUsers() async {
    _checkNotDisposed();
    final box = await _box('chat_users');
    return _safeDeserialize(
      box.values,
      (m) => userFromMap(m, onWarning: onWarning),
      boxName: 'users',
    );
  }

  @override
  Future<ChatUser?> getUser(String userId) async {
    _checkNotDisposed();
    final box = await _box('chat_users');
    final data = box.get(userId);
    if (data == null) return null;
    try {
      return userFromMap(Map<String, dynamic>.from(data), onWarning: onWarning);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteUser(String userId) async {
    _checkNotDisposed();
    final box = await _box('chat_users');
    await _safeWrite('deleteUser', () => box.delete(userId));
  }

  // Contacts

  @override
  Future<void> saveContacts(List<ChatContact> contacts) async {
    _checkNotDisposed();
    final box = await _box('chat_contacts');
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
  }

  @override
  Future<List<ChatContact>> getContacts() async {
    _checkNotDisposed();
    final box = await _box('chat_contacts');
    return _safeDeserialize(box.values, contactFromMap, boxName: 'contacts');
  }

  // Unreads

  @override
  Future<void> saveUnreads(List<UnreadRoom> unreads) async {
    _checkNotDisposed();
    final box = await _box('chat_unreads');
    final entries = <String, Map<dynamic, dynamic>>{};
    for (final u in unreads) {
      entries[u.roomId] = unreadRoomToMap(u);
    }
    await _safeWrite('saveUnreads', () => box.putAll(entries));
  }

  @override
  Future<List<UnreadRoom>> getUnreads() async {
    _checkNotDisposed();
    final box = await _box('chat_unreads');
    return _safeDeserialize(
      box.values,
      (m) => unreadRoomFromMap(m, onWarning: onWarning),
      boxName: 'unreads',
    );
  }

  // Invited rooms

  @override
  Future<void> saveInvitedRooms(List<InvitedRoom> invitedRooms) async {
    _checkNotDisposed();
    final box = await _box('chat_invited');
    await _safeWrite('saveInvitedRooms clear', () => box.clear());
    final entries = <int, Map<dynamic, dynamic>>{};
    for (var i = 0; i < invitedRooms.length; i++) {
      entries[i] = invitedRoomToMap(invitedRooms[i]);
    }
    await _safeWrite('saveInvitedRooms putAll', () => box.putAll(entries));
  }

  @override
  Future<List<InvitedRoom>> getInvitedRooms() async {
    _checkNotDisposed();
    final box = await _box('chat_invited');
    return _safeDeserialize(box.values, invitedRoomFromMap, boxName: 'invited');
  }

  // Unreads (individual)

  @override
  Future<void> deleteUnread(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_unreads');
    await _safeWrite('deleteUnread', () => box.delete(roomId));
  }

  // Offline queue

  @override
  Future<void> saveOfflineQueue(List<Map<String, dynamic>> operations) async {
    _checkNotDisposed();
    final box = await _box('chat_offline_queue');
    final limited =
        maxOfflineQueueSize != null && operations.length > maxOfflineQueueSize!
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
  }

  @override
  Future<List<Map<String, dynamic>>> getOfflineQueue() async {
    _checkNotDisposed();
    final box = await _box('chat_offline_queue');
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> clearOfflineQueue() async {
    _checkNotDisposed();
    final box = await _box('chat_offline_queue');
    await _safeWrite('clearOfflineQueue', () => box.clear());
  }

  // Reactions

  @override
  Future<void> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  ) async {
    _checkNotDisposed();
    final box = await _box('chat_reactions_${_sanitizeForBoxName(roomId)}');
    await _safeWrite(
      'saveReactions',
      () =>
          box.put(messageId, {'items': reactions.map(reactionToMap).toList()}),
    );
  }

  @override
  Future<List<AggregatedReaction>> getReactions(
    String roomId,
    String messageId,
  ) async {
    _checkNotDisposed();
    final box = await _box('chat_reactions_${_sanitizeForBoxName(roomId)}');
    final raw = box.get(messageId);
    if (raw == null) return [];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(
      items,
      (m) => reactionFromMap(m),
      boxName: 'reactions',
    );
  }

  @override
  Future<void> deleteReactions(String roomId, String messageId) async {
    _checkNotDisposed();
    final box = await _box('chat_reactions_${_sanitizeForBoxName(roomId)}');
    await _safeWrite('deleteReactions', () => box.delete(messageId));
  }

  // Pins

  @override
  Future<void> savePins(String roomId, List<MessagePin> pins) async {
    _checkNotDisposed();
    final box = await _box('chat_pins');
    await _safeWrite(
      'savePins',
      () => box.put(roomId, {'items': pins.map(pinToMap).toList()}),
    );
  }

  @override
  Future<List<MessagePin>> getPins(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_pins');
    final raw = box.get(roomId);
    if (raw == null) return [];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(items, (m) => pinFromMap(m), boxName: 'pins');
  }

  @override
  Future<void> deletePin(String roomId, String messageId) async {
    _checkNotDisposed();
    final box = await _box('chat_pins');
    final raw = box.get(roomId);
    if (raw == null) return;
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    final filtered = items
        .where((m) => Map<String, dynamic>.from(m)['messageId'] != messageId)
        .toList();
    await _safeWrite('deletePin', () => box.put(roomId, {'items': filtered}));
  }

  // Read receipts

  @override
  Future<void> saveReceipts(String roomId, List<ReadReceipt> receipts) async {
    _checkNotDisposed();
    final box = await _box('chat_receipts');
    await _safeWrite(
      'saveReceipts',
      () => box.put(roomId, {'items': receipts.map(receiptToMap).toList()}),
    );
  }

  @override
  Future<List<ReadReceipt>> getReceipts(String roomId) async {
    _checkNotDisposed();
    final box = await _box('chat_receipts');
    final raw = box.get(roomId);
    if (raw == null) return [];
    final items = (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    return _safeDeserialize(
      items,
      (m) => receiptFromMap(m),
      boxName: 'receipts',
    );
  }

  // TTL expiration

  Future<void> _expireOldMessages() async {
    final cutoffPrefix = DateTime.now()
        .toUtc()
        .subtract(messageTtl!)
        .toIso8601String();
    for (final roomId in _getMessageRoomIds()) {
      final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
      final box = await _box(name);
      // Keys are `{timestamp}_{id}`, sorted ascending. All keys < cutoff are expired.
      final keysToRemove = box.keys
          .cast<String>()
          .where((k) => k.compareTo(cutoffPrefix) < 0)
          .toList();
      if (keysToRemove.isNotEmpty) {
        await _safeWrite(
          'expireOldMessages',
          () => box.deleteAll(keysToRemove),
        );
        onMetric?.call('cache_ttl_expired', {
          'roomId': roomId,
          'count': keysToRemove.length,
        });
      }
    }
  }

  // Entity eviction

  Future<void> _evictRoomsIfNeeded() async {
    if (maxRooms == null) return;
    final box = await _box('chat_rooms');
    if (box.length <= maxRooms!) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxRooms!);
    await _safeWrite('evictRooms', () => box.deleteAll(toRemove));
    // Cascade: clean orphaned data for evicted rooms (best-effort, no rollback)
    final detailsBox = await _box('chat_room_details');
    final unreadsBox = await _box('chat_unreads');
    final invitedBox = await _box('chat_invited');
    final pinsBox = await _box('chat_pins');
    final receiptsBox = await _box('chat_receipts');
    for (final roomId in toRemove) {
      await _safeWrite('evictRooms details', () => detailsBox.delete(roomId));
      await _safeWrite('evictRooms unreads', () => unreadsBox.delete(roomId));
      await clearMessages(roomId);
      final reactionsBox = await _box(
        'chat_reactions_${_sanitizeForBoxName(roomId)}',
      );
      await _safeWrite('evictRooms reactions', () => reactionsBox.clear());
      await _safeWrite('evictRooms pins', () => pinsBox.delete(roomId));
      await _safeWrite('evictRooms receipts', () => receiptsBox.delete(roomId));
      await _safeWrite(
        'evictRooms clearedAt',
        () => _metaBox.delete('clearedAt_$roomId'),
      );
      await clearPendingMessages(roomId);
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
    final box = await _box('chat_users');
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
    final roomsBox = await _box('chat_rooms');
    final detailsBox = await _box('chat_room_details');
    final usersBox = await _box('chat_users');
    final contactsBox = await _box('chat_contacts');
    final unreadsBox = await _box('chat_unreads');
    final invitedBox = await _box('chat_invited');

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

    final roomsBox = await _box('chat_rooms');
    final detailsBox = await _box('chat_room_details');
    final usersBox = await _box('chat_users');
    final contactsBox = await _box('chat_contacts');
    final unreadsBox = await _box('chat_unreads');
    final invitedBox = await _box('chat_invited');

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

  // Lifecycle

  @override
  Future<void> clear() async {
    // Clear already-open boxes
    for (final box in _openBoxes.values) {
      if (box.isOpen) {
        await _safeWrite('clear box', () => box.clear());
      }
    }
    // Delete message boxes that aren't open from disk
    for (final roomId in _getMessageRoomIds()) {
      final name = 'chat_messages_${_sanitizeForBoxName(roomId)}';
      if (!_openBoxes.containsKey(name)) {
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
    }
    _msgIdIndex.clear();
    if (_metaBox.isOpen) {
      await _safeWrite('clear metaBox', () => _metaBox.clear());
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _ttlTimer?.cancel();
    _ttlTimer = null;
    for (final box in _openBoxes.values) {
      if (box.isOpen) await box.close();
    }
    _openBoxes.clear();
    if (_metaBox.isOpen) await _metaBox.close();
  }
}
