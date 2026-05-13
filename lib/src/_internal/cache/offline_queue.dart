import 'dart:collection';
import 'dart:math';

import '../../models/message.dart';
import 'local_datasource.dart';

sealed class PendingOperation {
  final String id;
  final DateTime createdAt;
  int attempts;
  DateTime? nextRetryAt;

  PendingOperation({
    required this.id,
    DateTime? createdAt,
    this.attempts = 0,
  }) : createdAt = createdAt ?? DateTime.now();
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
    super.createdAt,
    super.attempts,
  });
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
  });
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
  });
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
  });
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
  });
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
  });
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
  });
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
  });
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
  });
}

class OfflineQueue {
  final int maxRetries;
  final Duration maxAge;
  final int maxQueueSize;
  final void Function(PendingOperation op, String reason)? onOperationDropped;
  final void Function(String level, String message)? logger;
  final Queue<PendingOperation> _queue = Queue();
  final ChatLocalDatasource? _store;
  bool _processing = false;
  final DateTime Function() _clock;
  final Random _random;

  OfflineQueue({
    this.maxRetries = 5,
    this.maxAge = const Duration(hours: 24),
    this.maxQueueSize = 100,
    this.onOperationDropped,
    this.logger,
    ChatLocalDatasource? store,
    DateTime Function()? clock,
    Random? random,
  })  : _store = store,
        _clock = clock ?? (() => DateTime.now()),
        _random = random ?? Random();

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  List<PendingOperation> get pending => _queue.toList();

  Future<void> restore() async {
    if (_store == null) return;
    final maps = await _store.getOfflineQueue();
    for (final map in maps) {
      final op = _deserializeOperation(map);
      if (op != null) _queue.add(op);
    }
  }

  void enqueue(PendingOperation operation) {
    if (_queue.length >= maxQueueSize) {
      onOperationDropped?.call(operation, 'queue_full');
      return;
    }
    _queue.add(operation);
    _persist();
  }

  Future<void> processQueue(
      Future<bool> Function(PendingOperation op) executor) async {
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
          _queue.add(op);
          continue;
        }

        processed++;

        op.attempts++;

        final success = await executor(op);
        if (success) {
          _persist();
          continue;
        } else if (op.attempts >= maxRetries) {
          onOperationDropped?.call(op, 'max_retries');
        } else {
          final delaySecs =
              min(pow(2, op.attempts).toInt(), 30) + _random.nextInt(3);
          op.nextRetryAt = _clock().add(Duration(seconds: delaySecs));
          _queue.add(op);
        }
      }
      _persist();
    } finally {
      _processing = false;
    }
  }

  void clear() {
    _queue.clear();
    _persist();
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
      await _store
          .saveOfflineQueue(_queue.map(_serializeOperation).toList());
    }
  }

  static Map<String, dynamic> _serializeOperation(PendingOperation op) {
    final base = {
      'id': op.id,
      'createdAt': op.createdAt.toIso8601String(),
      'attempts': op.attempts,
    };
    switch (op) {
      case PendingSendMessage():
        return {
          ...base,
          'type': 'sendMessage',
          'roomId': op.roomId,
          if (op.text != null) 'text': op.text,
          'messageType': op.messageType.name,
          if (op.referencedMessageId != null)
            'referencedMessageId': op.referencedMessageId,
          if (op.reaction != null) 'reaction': op.reaction,
          if (op.attachmentUrl != null) 'attachmentUrl': op.attachmentUrl,
          if (op.sourceRoomId != null) 'sourceRoomId': op.sourceRoomId,
          if (op.metadata != null) 'metadata': op.metadata,
          if (op.tempId != null) 'tempId': op.tempId,
        };
      case PendingSendDirectMessage():
        return {
          ...base,
          'type': 'sendDirectMessage',
          'contactUserId': op.contactUserId,
          if (op.text != null) 'text': op.text,
          'messageType': op.messageType.name,
          if (op.referencedMessageId != null)
            'referencedMessageId': op.referencedMessageId,
          if (op.reaction != null) 'reaction': op.reaction,
          if (op.attachmentUrl != null) 'attachmentUrl': op.attachmentUrl,
          if (op.metadata != null) 'metadata': op.metadata,
        };
      case PendingEditMessage():
        return {
          ...base,
          'type': 'editMessage',
          'roomId': op.roomId,
          'messageId': op.messageId,
          'text': op.text,
          if (op.metadata != null) 'metadata': op.metadata,
        };
      case PendingDeleteMessage():
        return {
          ...base,
          'type': 'deleteMessage',
          'roomId': op.roomId,
          'messageId': op.messageId,
        };
      case PendingDeleteReaction():
        return {
          ...base,
          'type': 'deleteReaction',
          'roomId': op.roomId,
          'messageId': op.messageId,
        };
      case PendingCreateRoom():
        return {
          ...base,
          'type': 'createRoom',
          'name': op.name,
          'audience': op.audience,
          'members': op.members,
          if (op.type != null) 'roomType': op.type,
          if (op.subject != null) 'subject': op.subject,
        };
      case PendingUpdateRoomConfig():
        return {
          ...base,
          'type': 'updateRoomConfig',
          'roomId': op.roomId,
          if (op.name != null) 'name': op.name,
          if (op.subject != null) 'subject': op.subject,
          if (op.avatar != null) 'avatar': op.avatar,
          if (op.allowInvitations != null)
            'allowInvitations': op.allowInvitations,
        };
      case PendingAddMember():
        return {
          ...base,
          'type': 'addMember',
          'roomId': op.roomId,
          'userId': op.userId,
          if (op.role != null) 'role': op.role,
        };
      case PendingRemoveMember():
        return {
          ...base,
          'type': 'removeMember',
          'roomId': op.roomId,
          'userId': op.userId,
        };
    }
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
