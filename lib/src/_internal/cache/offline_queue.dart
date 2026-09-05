import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/message.dart';
import '../../cache/local_datasource.dart';
import 'cache_manager.dart' show MetricCallback;

part 'pending_operations.dart';

/// Memoizes the base64 encoding of a queued attachment's bytes, keyed by
/// the [Uint8List] instance itself. `OfflineQueue._persist` re-serializes
/// the WHOLE queue (every pending op's `toJson()`) on every enqueue and on
/// every drain step — without this cache a single large queued attachment
/// would be base64-re-encoded on the UI isolate on every one of those
/// persists, even though its bytes never change between them. The same
/// [Uint8List] reference survives every [PendingSendAttachment.withRetry]
/// copy (only `attempts`/`nextRetryAt` change on retry), so the cache stays
/// hot for the operation's whole lifetime in the queue; it naturally misses
/// again after a restart, where [OfflineQueue.restore] decodes a fresh
/// [Uint8List] from disk anyway.
final Expando<String> _attachmentBase64Cache = Expando<String>(
  'attachmentBase64Cache',
);

String _cachedBase64OfBytes(Uint8List bytes) {
  final cached = _attachmentBase64Cache[bytes];
  if (cached != null) return cached;
  final encoded = base64Encode(bytes);
  _attachmentBase64Cache[bytes] = encoded;
  return encoded;
}

/// Executes one pending operation against the server. Returns `true` on
/// success (op is removed from the queue) or `false` on a transient
/// failure (op is re-queued with exponential backoff). Throwing is
/// treated the same as `false`. Set via [OfflineQueue.executor] at
/// construction so the queue is self-contained and a caller never
/// passes the closure on every `drain()`.
typedef PendingOperationExecutor = Future<bool> Function(PendingOperation op);

class OfflineQueue {
  /// Upper bound on the exponential backoff between retry attempts.
  /// Above this cap, each subsequent attempt waits the same duration
  /// regardless of how many times the operation has failed.
  static const int _maxBackoffSecs = 30;

  /// Random jitter (in seconds) added on top of the exponential backoff
  /// so a fleet of clients reconnecting at once does not stampede the
  /// backend.
  static const int _jitterRangeSecs = 3;

  final int maxRetries;
  final Duration maxAge;
  final int maxQueueSize;
  final void Function(PendingOperation op, String reason)? onOperationDropped;
  final void Function(String level, String message)? logger;
  final MetricCallback? metricCallback;
  final Queue<PendingOperation> _queue = Queue();
  final ChatLocalDatasource? _store;
  bool _processing = false;
  final DateTime Function() _clock;
  final Random _random;

  /// Injected executor for [drain]. Settable post-construction via
  /// [bindExecutor] because the canonical wiring (`NomaChatClient`)
  /// constructs the queue early and only knows how to execute pending
  /// ops once its sub-APIs are wired. When `null` the queue can still
  /// [enqueue], [restore], and persist; only [drain] requires it.
  PendingOperationExecutor? _executor;

  /// Binds the executor closure used by [drain]. Idempotent — calling
  /// twice with the same closure is fine; a different closure replaces
  /// the previous binding.
  void bindExecutor(PendingOperationExecutor executor) {
    _executor = executor;
  }

  OfflineQueue({
    PendingOperationExecutor? executor,
    this.maxRetries = 5,
    this.maxAge = const Duration(hours: 24),
    this.maxQueueSize = 100,
    this.onOperationDropped,
    this.logger,
    this.metricCallback,
    ChatLocalDatasource? store,
    DateTime Function()? clock,
    Random? random,
  }) : _executor = executor,
       _store = store,
       _clock = clock ?? (() => DateTime.now()),
       _random = random ?? Random();

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  List<PendingOperation> get pending => _queue.toList();

  /// Reloads persisted operations into the in-memory queue. Deduplicates
  /// by operation `id` against whatever is already queued, so a repeated
  /// `restore()` — e.g. the documented background→foreground
  /// disconnect/connect cycle calling it on every `connect()` — never
  /// duplicates pending sends (N enqueued ops would otherwise become 2N
  /// after the second restore and fire twice on reconnect).
  Future<void> restore() async {
    if (_store == null) return;
    final maps = (await _store.getOfflineQueue()).dataOrNull ?? const [];
    final seenIds = _queue.map((op) => op.id).toSet();
    for (final map in maps) {
      final op = _deserializeOperation(map);
      if (op == null) continue;
      if (seenIds.add(op.id)) _queue.add(op);
    }
  }

  void enqueue(PendingOperation operation) {
    if (_queue.length >= maxQueueSize) {
      onOperationDropped?.call(operation, 'queue_full');
      return;
    }
    _queue.add(operation);
    _persistSilent();
  }

  /// Drops every queued operation enqueued for the optimistic row
  /// [optimisticId], returning how many went.
  ///
  /// The counterpart to [enqueue] for a send the user took back. Once a
  /// failure surfaces, the queue is where that send lives on: without this
  /// a bubble the user discarded still goes out on the next drain, and one
  /// re-driven under a fresh id goes out twice. Both are irreversible —
  /// the message lands in a room somebody else is reading.
  ///
  /// An operation an in-flight drain already handed to the executor is
  /// past recall: it left the queue when the drain picked it up.
  int removeForOptimisticId(String optimisticId) {
    final kept = _queue
        .where((op) => op.optimisticId != optimisticId)
        .toList(growable: false);
    final removed = _queue.length - kept.length;
    if (removed == 0) return 0;
    _queue
      ..clear()
      ..addAll(kept);
    _persistSilent();
    return removed;
  }

  /// Drains the queue using the executor bound via [bindExecutor] (or
  /// the constructor). Idempotent — a re-entrant call returns
  /// immediately so the host can wire `drain()` to multiple triggers
  /// (reconnect, app-resume, tick) without racing itself.
  ///
  /// Throws [StateError] when no executor is bound — the queue is in
  /// "passive" mode and the caller is misusing it.
  Future<void> drain() {
    final exec = _executor;
    if (exec == null) {
      throw StateError(
        'OfflineQueue.drain() called without an executor — use '
        'bindExecutor() or pass one to the constructor.',
      );
    }
    return _drainWith(exec);
  }

  /// Test-only escape hatch: drain with an ad-hoc executor (bypasses the
  /// constructor-injected [executor]). Keeps the unit tests in
  /// `offline_queue_test.dart` self-contained without forcing every
  /// test to construct a full closure-bearing queue.
  @visibleForTesting
  Future<void> processQueue(PendingOperationExecutor executor) =>
      _drainWith(executor);

  Future<void> _drainWith(PendingOperationExecutor executor) async {
    if (_processing) return;
    _processing = true;

    try {
      final now = _clock();
      final snapshot = _queue.length;
      var processed = 0;
      while (processed < snapshot && _queue.isNotEmpty) {
        final op = _queue.removeFirst();

        if (now.difference(op.createdAt) > maxAge) {
          onOperationDropped?.call(op, 'ttl_expired');
          processed++;
          continue;
        }

        if (op.nextRetryAt != null && _clock().isBefore(op.nextRetryAt!)) {
          // Still in backoff: put it back at the front and stop this drain
          // pass instead of cycling every remaining op through a no-op
          // "still waiting" check. Preserves FIFO order (no rotation to the
          // back of the queue) and keeps a drain with many backing-off ops
          // O(1) instead of O(queue length).
          _queue.addFirst(op);
          break;
        }

        processed++;

        // Immutable retry — instead of mutating attempts/nextRetryAt
        // on the existing op, copy with the bumped attempts and
        // execute the new instance. Failed attempts re-enqueue a new
        // copyWith carrying the backoff timestamp.
        final attempting = op.withRetry(attempts: op.attempts + 1);
        final success = await executor(attempting);
        if (success) {
          _persist();
          continue;
        } else if (attempting.attempts >= maxRetries) {
          onOperationDropped?.call(attempting, 'max_retries');
        } else {
          final delaySecs =
              min(pow(2, attempting.attempts).toInt(), _maxBackoffSecs) +
              _random.nextInt(_jitterRangeSecs);
          _queue.add(
            attempting.withRetry(
              nextRetryAt: _clock().add(Duration(seconds: delaySecs)),
            ),
          );
        }
      }
      _persist();
    } finally {
      _processing = false;
    }
  }

  void clear() {
    _queue.clear();
    _persistSilent();
  }

  Future<void> dispose() async {
    await _persist();
    _queue.clear();
  }

  Future<void> _persist() async {
    if (_store == null) return;
    if (_queue.isEmpty) {
      await _store.clearOfflineQueue();
    } else {
      await _store.saveOfflineQueue(_queue.map((op) => op.toJson()).toList());
    }
    metricCallback?.call('offline_queue_depth', {'depth': _queue.length});
  }

  /// Fire-and-forget wrapper for [_persist]. Logs any error instead of
  /// letting the unhandled async exception crash the host app. Use from
  /// sync entry points (`enqueue`, `clear`) where awaiting would force
  /// callers to `async`.
  void _persistSilent() {
    _persist().catchError((Object error, StackTrace stack) {
      logger?.call(
        'warn',
        'OfflineQueue: persist failed ($error). Queue still in-memory; '
            'next successful _persist() will catch up.',
      );
    });
  }

  static MessageType _parseMessageType(String? type) => switch (type) {
    'attachment' => MessageType.attachment,
    'reaction' => MessageType.reaction,
    'reply' => MessageType.reply,
    'audio' => MessageType.audio,
    'forward' => MessageType.forward,
    _ => MessageType.regular,
  };

  PendingOperation? _deserializeOperation(Map<String, dynamic> map) {
    try {
      final id = map['id'] as String;
      final createdAt = DateTime.parse(map['createdAt'] as String);
      final attempts = map['attempts'] as int? ?? 0;

      switch (map['type'] as String?) {
        case 'sendMessage':
          return PendingSendMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            text: map['text'] as String?,
            messageType: _parseMessageType(map['messageType'] as String?),
            referencedMessageId: map['referencedMessageId'] as String?,
            reaction: map['reaction'] as String?,
            attachmentUrl: map['attachmentUrl'] as String?,
            attachmentId: map['attachmentId'] as String?,
            sourceRoomId: map['sourceRoomId'] as String?,
            metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
            tempId: map['tempId'] as String?,
            clientMessageId: map['clientMessageId'] as String?,
          );
        case 'sendAttachment':
          return PendingSendAttachment(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            bytes: base64Decode(map['bytes'] as String),
            mimeType: map['mimeType'] as String,
            fileName: map['fileName'] as String?,
            messageType: _parseMessageType(map['messageType'] as String?),
            text: map['text'] as String?,
            referencedMessageId: map['referencedMessageId'] as String?,
            metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
            tempId: map['tempId'] as String?,
            clientMessageId: map['clientMessageId'] as String?,
          );
        case 'sendDirectMessage':
          return PendingSendDirectMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            contactUserId: map['contactUserId'] as String,
            text: map['text'] as String?,
            messageType: _parseMessageType(map['messageType'] as String?),
            referencedMessageId: map['referencedMessageId'] as String?,
            reaction: map['reaction'] as String?,
            attachmentUrl: map['attachmentUrl'] as String?,
            metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
            clientMessageId: map['clientMessageId'] as String?,
          );
        case 'editMessage':
          return PendingEditMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
            text: map['text'] as String,
            metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
          );
        case 'deleteMessage':
          return PendingDeleteMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'deleteReaction':
          return PendingDeleteReaction(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'addReaction':
          return PendingAddReaction(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
            emoji: map['emoji'] as String,
          );
        case 'pinMessage':
          return PendingPinMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'unpinMessage':
          return PendingUnpinMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'starMessage':
          return PendingStarMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'unstarMessage':
          return PendingUnstarMessage(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            messageId: map['messageId'] as String,
          );
        case 'createRoom' || 'create_room':
          return PendingCreateRoom(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            name: map['name'] as String,
            audience: map['audience'] as String,
            members: (map['members'] as List).cast<String>(),
            type: map['roomType'] as String?,
            subject: map['subject'] as String?,
            idempotencyKey: map['idempotencyKey'] as String?,
          );
        case 'updateRoomConfig' || 'update_room_config':
          return PendingUpdateRoomConfig(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            name: map['name'] as String?,
            subject: map['subject'] as String?,
            avatar: map['avatar'] as String?,
            allowInvitations: map['allowInvitations'] as bool?,
            idempotencyKey: map['idempotencyKey'] as String?,
          );
        case 'addMember' || 'add_member':
          return PendingAddMember(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            userId: map['userId'] as String,
            role: map['role'] as String?,
            idempotencyKey: map['idempotencyKey'] as String?,
          );
        case 'removeMember' || 'remove_member':
          return PendingRemoveMember(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            userId: map['userId'] as String,
            idempotencyKey: map['idempotencyKey'] as String?,
          );
        default:
          return null;
      }
    } catch (e) {
      logger?.call('warn', 'OfflineQueue: failed to deserialize operation: $e');
      return null;
    }
  }
}
