import 'dart:convert';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../../models/presence.dart';
import '../../models/room_user.dart';
import '../mappers/message_mapper.dart';

class EventParser {
  static void Function(String level, String message)? logger;

  static ChatEvent? parseJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null) return null;

    return switch (type) {
      'new_message' => _parseNewMessage(json),
      'message_updated' => _parseMessageUpdated(json),
      'message_deleted' => _parseMessageDeleted(json),
      'room_created' => _parseRoomCreated(json),
      'room_updated' => _parseRoomUpdated(json),
      'room_deleted' => _parseRoomDeleted(json),
      'typing' => _parseUserActivity(json),
      'presence' || 'presence_changed' => _parsePresenceChanged(json),
      'unread_updated' => _parseUnreadUpdated(json),
      'user_joined' => _parseUserJoined(json),
      'user_left' => _parseUserLeft(json),
      'user_role_changed' => _parseUserRoleChanged(json),
      'receipt_updated' => _parseReceiptUpdated(json),
      'reaction_added' => _parseReactionAddedNative(json),
      'reaction_deleted' => _parseReactionDeleted(json),
      'broadcast' => _parseBroadcast(json),
      _ => () {
          logger?.call('warn', 'EventParser: unknown event type "$type"');
          return null;
        }(),
    };
  }

  static ChatEvent? parseNrte(String rawMessage) {
    final separatorIndex = rawMessage.indexOf(';');
    if (separatorIndex < 0) return null;

    final jsonPayload = rawMessage.substring(separatorIndex + 1);
    try {
      final data = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final topic = rawMessage.substring(0, separatorIndex);
      data['type'] ??= _inferTypeFromTopic(topic);
      return parseJson(data);
    } catch (e) {
      logger?.call(
        'warn',
        'EventParser: failed to parse NRTE message: $e',
      );
      return null;
    }
  }

  static String? _inferTypeFromTopic(String topic) {
    final parts = topic.split(':');
    return parts.length > 1 ? parts.last : null;
  }

  static ChatEvent? _parseNewMessage(Map<String, dynamic> json) {
    final msg = _messageFromEvent(json);
    if (msg == null) return null;
    final roomId = json['roomId'] as String?;
    if (roomId == null || roomId.isEmpty) return null;
    if (msg.messageType == MessageType.reaction && msg.reaction != null) {
      return ChatEvent.reactionAdded(
        roomId: roomId,
        messageId: msg.referencedMessageId ?? msg.id,
        userId: msg.from,
        reaction: msg.reaction!,
      );
    }
    return ChatEvent.newMessage(message: msg, roomId: roomId);
  }

  static ChatEvent? _parseMessageUpdated(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final messageId = json['messageId'] as String?;
    if (roomId == null || messageId == null) return null;
    return ChatEvent.messageUpdated(roomId: roomId, messageId: messageId);
  }

  static ChatEvent? _parseMessageDeleted(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final messageId = json['messageId'] as String?;
    if (roomId == null || messageId == null) return null;
    return ChatEvent.messageDeleted(roomId: roomId, messageId: messageId);
  }

  static ChatEvent? _parseRoomCreated(Map<String, dynamic> json) {
    final room = json['room'] as Map<String, dynamic>?;
    final roomId = (json['roomId'] ?? room?['roomId'] ?? room?['id']) as String?;
    if (roomId == null) return null;
    return ChatEvent.roomCreated(roomId: roomId);
  }

  static ChatEvent? _parseRoomUpdated(Map<String, dynamic> json) {
    final room = json['room'] as Map<String, dynamic>?;
    final roomId = (json['roomId'] ?? room?['roomId'] ?? room?['id']) as String?;
    if (roomId == null) return null;
    return ChatEvent.roomUpdated(roomId: roomId);
  }

  static ChatEvent? _parseRoomDeleted(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    if (roomId == null) return null;
    return ChatEvent.roomDeleted(roomId: roomId);
  }

  static ChatEvent? _parseUserActivity(Map<String, dynamic> json) {
    final userId = (json['userId'] ?? json['from']) as String?;
    if (userId == null) return null;
    final activityStr = _fieldOrDefault(
      json, 'activity', 'startsTyping', 'typing',
    );
    final activity = activityStr == 'stopsTyping'
        ? ChatActivity.stopsTyping
        : ChatActivity.startsTyping;
    final contactId = json['contactId'] as String?;
    if (contactId != null) {
      return ChatEvent.dmActivity(
          contactId: contactId, userId: userId, activity: activity);
    }
    final roomId = json['roomId'] as String?;
    if (roomId == null) return null;
    return ChatEvent.userActivity(
        roomId: roomId, userId: userId, activity: activity);
  }

  static ChatEvent? _parsePresenceChanged(Map<String, dynamic> json) {
    final userId = json['userId'] as String?;
    if (userId == null) return null;
    final statusStr = _fieldOrDefault(
      json, 'status', 'offline', 'presence_changed',
    );
    final status = _parsePresenceStatus(statusStr);
    return ChatEvent.presenceChanged(
      userId: userId,
      status: status,
      online: json['online'] as bool? ?? status != PresenceStatus.offline,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      statusText: json['statusText'] as String?,
    );
  }

  static PresenceStatus _parsePresenceStatus(String status) => switch (status) {
        'available' => PresenceStatus.available,
        'away' => PresenceStatus.away,
        'busy' => PresenceStatus.busy,
        'dnd' => PresenceStatus.dnd,
        _ => PresenceStatus.offline,
      };

  static ChatEvent? _parseUnreadUpdated(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    if (roomId == null) return null;
    return ChatEvent.unreadUpdated(
      roomId: roomId,
      count: json['count'] as int? ?? json['unreadMessages'] as int? ?? 0,
    );
  }

  static ChatEvent? _parseUserJoined(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final userId = json['userId'] as String?;
    if (roomId == null || userId == null) return null;
    return ChatEvent.userJoined(roomId: roomId, userId: userId);
  }

  static ChatEvent? _parseUserLeft(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final userId = json['userId'] as String?;
    if (roomId == null || userId == null) return null;
    return ChatEvent.userLeft(roomId: roomId, userId: userId);
  }

  static ChatEvent? _parseUserRoleChanged(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final userId = json['userId'] as String?;
    if (roomId == null || userId == null) return null;
    final roleStr = _fieldOrDefault(
      json, 'role', 'member', 'user_role_changed',
    );
    final role = switch (roleStr) {
      'owner' => RoomRole.owner,
      'admin' => RoomRole.admin,
      _ => RoomRole.member,
    };
    return ChatEvent.userRoleChanged(
        roomId: roomId, userId: userId, role: role);
  }

  static ChatEvent? _parseReceiptUpdated(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final messageId = json['messageId'] as String?;
    if (roomId == null || messageId == null) return null;
    final statusStr = _fieldOrDefault(
      json, 'status', 'read', 'receipt_updated',
    );
    final status = switch (statusStr) {
      'sent' => ReceiptStatus.sent,
      'delivered' => ReceiptStatus.delivered,
      _ => ReceiptStatus.read,
    };
    final fromUserId = json['fromUserId'] as String? ?? json['userId'] as String?;
    return ChatEvent.receiptUpdated(
        roomId: roomId, messageId: messageId, status: status, fromUserId: fromUserId);
  }

  static ChatEvent? _parseReactionAddedNative(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final messageId = json['messageId'] as String?;
    final userId = json['userId'] as String?;
    final reaction = (json['emoji'] ?? json['reaction']) as String?;
    if (roomId == null || messageId == null || userId == null || reaction == null) {
      return null;
    }
    return ChatEvent.reactionAdded(
      roomId: roomId,
      messageId: messageId,
      userId: userId,
      reaction: reaction,
    );
  }

  static ChatEvent? _parseReactionDeleted(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String?;
    final messageId = json['messageId'] as String?;
    if (roomId == null || messageId == null) return null;
    return ChatEvent.reactionDeleted(roomId: roomId, messageId: messageId);
  }

  static ChatEvent? _parseBroadcast(Map<String, dynamic> json) {
    final message = json['message'] as String?;
    if (message == null) return null;
    return ChatEvent.broadcast(message: message);
  }

  static String _fieldOrDefault(
    Map<String, dynamic> json,
    String field,
    String defaultValue,
    String eventType,
  ) {
    final value = json[field] as String?;
    if (value != null) return value;
    logger?.call(
      'warn',
      'EventParser: "$eventType" event missing "$field" field, '
          'defaulting to "$defaultValue"',
    );
    return defaultValue;
  }

  static ChatMessage? _messageFromEvent(Map<String, dynamic> json) {
    final messageData = json['message'] as Map<String, dynamic>? ?? json;
    final id = (messageData['messageId'] ??
        messageData['idMessage'] ??
        messageData['id']) as String?;
    final from = (messageData['from'] ??
        messageData['fromJid'] ??
        messageData['userId'] ??
        json['userId']) as String?;
    if (id == null || from == null) return null;
    return MessageMapper.fromJson({
      ...messageData,
      'id': id,
      'from': from,
      'text': messageData['text'] ?? messageData['body'],
      'timestamp': messageData['timestamp'] ??
          json['timestamp'] ??
          DateTime.now().toIso8601String(),
    });
  }

}
