import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/message.dart';
import '../../cache/local_datasource.dart';
import 'cache_manager.dart' show MetricCallback;

sealed class PendingOperation {
  final String id;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextRetryAt;

  PendingOperation({
    required this.id,
    DateTime? createdAt,
    this.attempts = 0,
    this.nextRetryAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Returns a copy with bumped retry metadata. The drain loop calls
  /// this after a failed attempt to re-enqueue the same operation
  /// with `attempts + 1` and an optional `nextRetryAt` backoff
  /// timestamp. Subclasses preserve every other field unchanged.
  PendingOperation withRetry({int? attempts, DateTime? nextRetryAt});

  /// Serializes this operation to a `Map` suitable for the
  /// [ChatLocalDatasource.saveOfflineQueue] hand-off. Every concrete
  /// subclass overrides this with its own payload, including a `'type'`
  /// discriminator (`sendMessage`, `editMessage`, …) that
  /// [PendingOperation.fromJson] reads back to construct the right class.
  ///
  /// Concrete subclasses should spread [baseJson] first so the shared
  /// metadata (`id`, `createdAt`, `attempts`) lands at the top:
  ///
  /// ```dart
  /// @override
  /// Map<String, dynamic> toJson() => {
  ///   ...baseJson(),
  ///   'type': 'editMessage',
  ///   'roomId': roomId,
  ///   ...
  /// };
  /// ```
  Map<String, dynamic> toJson();

  /// Common fields shared by every concrete subclass. Spread at the top
  /// of each [toJson] map. Kept as a method (not a getter) for symmetry
  /// with the [toJson] override.
  Map<String, dynamic> baseJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };
}

final class PendingSendMessage extends PendingOperation {
  final String roomId;
  final String? text;
  final MessageType messageType;
  final String? referencedMessageId;
  final String? reaction;
  final String? attachmentUrl;
  final String? sourceRoomId;
  final Map<String, dynamic>? metadata;
  final String? tempId;

  /// Idempotency key reused across every retry of this queued send so a
  /// delivery that actually reached the server (before the failure
  /// surfaced) is not duplicated on drain. See [ChatMessagesApi.send].
  final String? clientMessageId;

  PendingSendMessage({
    required super.id,
    required this.roomId,
    this.text,
    this.messageType = MessageType.regular,
    this.referencedMessageId,
    this.reaction,
    this.attachmentUrl,
    this.sourceRoomId,
    this.metadata,
    this.tempId,
    this.clientMessageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'sendMessage',
    'roomId': roomId,
    if (text != null) 'text': text,
    'messageType': messageType.name,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
    if (metadata != null) 'metadata': metadata,
    if (tempId != null) 'tempId': tempId,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  @override
  PendingSendMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingSendMessage(
        id: id,
        roomId: roomId,
        text: text,
        messageType: messageType,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        sourceRoomId: sourceRoomId,
        metadata: metadata,
        tempId: tempId,
        clientMessageId: clientMessageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingSendDirectMessage extends PendingOperation {
  final String contactUserId;
  final String? text;
  final MessageType messageType;
  final String? referencedMessageId;
  final String? reaction;
  final String? attachmentUrl;
  final Map<String, dynamic>? metadata;

  PendingSendDirectMessage({
    required super.id,
    required this.contactUserId,
    this.text,
    this.messageType = MessageType.regular,
    this.referencedMessageId,
    this.reaction,
    this.attachmentUrl,
    this.metadata,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'sendDirectMessage',
    'contactUserId': contactUserId,
    if (text != null) 'text': text,
    'messageType': messageType.name,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (metadata != null) 'metadata': metadata,
  };

  @override
  PendingSendDirectMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingSendDirectMessage(
        id: id,
        contactUserId: contactUserId,
        text: text,
        messageType: messageType,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        metadata: metadata,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingEditMessage extends PendingOperation {
  final String roomId;
  final String messageId;
  final String text;
  final Map<String, dynamic>? metadata;

  PendingEditMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    required this.text,
    this.metadata,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'editMessage',
    'roomId': roomId,
    'messageId': messageId,
    'text': text,
    if (metadata != null) 'metadata': metadata,
  };

  @override
  PendingEditMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingEditMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        text: text,
        metadata: metadata,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingDeleteMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingDeleteMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'deleteMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingDeleteMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingDeleteMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingDeleteReaction extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingDeleteReaction({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'deleteReaction',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingDeleteReaction withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingDeleteReaction(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingCreateRoom extends PendingOperation {
  final String name;
  final String audience;
  final List<String> members;
  final String? type;
  final String? subject;

  PendingCreateRoom({
    required super.id,
    required this.name,
    required this.audience,
    required this.members,
    this.type,
    this.subject,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'createRoom',
    'name': name,
    'audience': audience,
    'members': members,
    if (type != null) 'roomType': type,
    if (subject != null) 'subject': subject,
  };

  @override
  PendingCreateRoom withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingCreateRoom(
        id: id,
        name: name,
        audience: audience,
        members: members,
        type: type,
        subject: subject,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingUpdateRoomConfig extends PendingOperation {
  final String roomId;
  final String? name;
  final String? subject;
  final String? avatar;
  final bool? allowInvitations;

  PendingUpdateRoomConfig({
    required super.id,
    required this.roomId,
    this.name,
    this.subject,
    this.avatar,
    this.allowInvitations,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'updateRoomConfig',
    'roomId': roomId,
    if (name != null) 'name': name,
    if (subject != null) 'subject': subject,
    if (avatar != null) 'avatar': avatar,
    if (allowInvitations != null) 'allowInvitations': allowInvitations,
  };

  @override
  PendingUpdateRoomConfig withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingUpdateRoomConfig(
        id: id,
        roomId: roomId,
        name: name,
        subject: subject,
        avatar: avatar,
        allowInvitations: allowInvitations,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingAddMember extends PendingOperation {
  final String roomId;
  final String userId;
  final String? role;

  PendingAddMember({
    required super.id,
    required this.roomId,
    required this.userId,
    this.role,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'addMember',
    'roomId': roomId,
    'userId': userId,
    if (role != null) 'role': role,
  };

  @override
  PendingAddMember withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingAddMember(
        id: id,
        roomId: roomId,
        userId: userId,
        role: role,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingRemoveMember extends PendingOperation {
  final String roomId;
  final String userId;

  PendingRemoveMember({
    required super.id,
    required this.roomId,
    required this.userId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'removeMember',
    'roomId': roomId,
    'userId': userId,
  };

  @override
  PendingRemoveMember withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingRemoveMember(
        id: id,
        roomId: roomId,
        userId: userId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
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
          // Still in backoff: defer to a later drain. Count it as processed so
          // the loop always advances towards `snapshot` — otherwise, when every
          // remaining op is in backoff, this while spins synchronously (no
          // await on this path) until the clock passes nextRetryAt, freezing
          // the isolate for up to the max backoff.
          _queue.add(op);
          processed++;
          continue;
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
            sourceRoomId: map['sourceRoomId'] as String?,
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
          );
        case 'addMember' || 'add_member':
          return PendingAddMember(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            userId: map['userId'] as String,
            role: map['role'] as String?,
          );
        case 'removeMember' || 'remove_member':
          return PendingRemoveMember(
            id: id,
            createdAt: createdAt,
            attempts: attempts,
            roomId: map['roomId'] as String,
            userId: map['userId'] as String,
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
