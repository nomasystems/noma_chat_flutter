import 'dart:convert';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../../models/presence.dart';
import '../../models/room_user.dart';
import '../mappers/message_mapper.dart';

class EventParser {
  static void Function(String level, String message)? logger;

  /// Highest realtime-event schema major version this SDK build understands.
  /// The backend may stamp events with a schema version (`schemaVersion` or
  /// `v`); a newer major than this signals fields/semantics the SDK predates.
  static const int supportedSchemaMajor = 1;

  /// Set once per process when a newer-major event is first seen, so the
  /// forward-compat warning is logged one time instead of per frame.
  static bool _loggedSchemaSkew = false;

  /// Safe cast: returns the value when it's a [String], `null` otherwise.
  /// Use instead of `as String?` for any field that comes from a JSON
  /// payload whose shape we don't fully control — protects against
  /// backends that send numbers / lists where strings are expected.
  static String? _asString(dynamic value) => value is String ? value : null;

  /// Safe casts for the other primitive field types we read off the wire.
  static int? _asInt(dynamic value) => value is int ? value : null;
  static bool? _asBool(dynamic value) => value is bool ? value : null;

  /// Reads the event's schema major version, if the backend stamped one.
  /// Accepts an int (`2`), a `MAJOR` string, or a `MAJOR.MINOR` string;
  /// returns `null` when absent or unparseable (treated as the current
  /// version — the field is optional and legacy events omit it).
  static int? _schemaMajor(Map<String, dynamic> json) {
    final raw = json['schemaVersion'] ?? json['v'];
    if (raw is int) return raw;
    if (raw is String) {
      final head = raw.split('.').first.trim();
      return int.tryParse(head);
    }
    return null;
  }

  static ChatEvent? parseJson(Map<String, dynamic> json) {
    final type = _asString(json['type']);
    if (type == null) return null;

    // Tolerant schema-version gate: a newer-major event may carry fields or
    // semantics this SDK build predates. We do NOT drop it — best-effort
    // parsing lets forward-compatible additive changes flow through — but we
    // warn once so the skew is diagnosable in the field.
    final major = _schemaMajor(json);
    if (major != null && major > supportedSchemaMajor && !_loggedSchemaSkew) {
      _loggedSchemaSkew = true;
      logger?.call(
        'warn',
        'EventParser: event schema major v$major is newer than the '
            'supported v$supportedSchemaMajor — parsing best-effort. '
            'Consider upgrading the noma_chat SDK.',
      );
    }

    return switch (type) {
      'new_message' => _parseNewMessage(json),
      'message_updated' => _parseMessageUpdated(json),
      'message_deleted' => _parseMessageDeleted(json),
      'room_created' => _parseRoomCreated(json),
      'room_updated' => _parseRoomUpdated(json),
      'room_deleted' => _parseRoomDeleted(json),
      'typing' => _parseUserActivity(json),
      'presence' || 'presence_changed' => _parsePresenceChanged(json),
      // `unread_updated` is never sent by the backend over the wire — it is
      // synthesized internally by the polling RefreshEngine. Parsed here only
      // as a defensive forward-compat path.
      'unread_updated' => _parseUnreadUpdated(json),
      'user_joined' => _parseUserJoined(json),
      'user_left' => _parseUserLeft(json),
      'user_role_changed' => _parseUserRoleChanged(json),
      'receipt_updated' => _parseReceiptUpdated(json),
      'message_acked' => _parseMessageAcked(json),
      'message_delivered' => _parseMessageDelivered(json),
      'reaction_added' => _parseReactionAddedNative(json),
      'reaction_deleted' => _parseReactionDeleted(json),
      'broadcast' => _parseBroadcast(json),
      'user_updated' => _parseUserUpdated(json),
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
      logger?.call('warn', 'EventParser: failed to parse NRTE message: $e');
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
    final roomId = _asString(json['roomId']);
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
    final roomId = _asString(json['roomId']);
    final messageId = _asString(json['messageId']);
    if (roomId == null || messageId == null) return null;
    // When the server bundles the full row inline (CHT `put_messages`,
    // `do_admin_put_message`), the SDK can apply the update without a
    // follow-up REST round-trip — there's no GET on
    // `/v1/rooms/:roomId/messages/:messageId` so the legacy
    // `_refreshMessage` path silently dropped admin edits.
    final message = json.containsKey('message')
        ? _messageFromEvent(json)
        : null;
    return ChatEvent.messageUpdated(
      roomId: roomId,
      messageId: messageId,
      message: message,
    );
  }

  static ChatEvent? _parseMessageDeleted(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final messageId = _asString(json['messageId']);
    if (roomId == null || messageId == null) return null;
    return ChatEvent.messageDeleted(roomId: roomId, messageId: messageId);
  }

  static ChatEvent? _parseRoomCreated(Map<String, dynamic> json) {
    final room = json['room'] is Map<String, dynamic>
        ? json['room'] as Map<String, dynamic>
        : null;
    final roomId =
        _asString(json['roomId']) ??
        _asString(room?['roomId']) ??
        _asString(room?['id']);
    if (roomId == null) return null;
    return ChatEvent.roomCreated(roomId: roomId);
  }

  static ChatEvent? _parseRoomUpdated(Map<String, dynamic> json) {
    final room = json['room'] is Map<String, dynamic>
        ? json['room'] as Map<String, dynamic>
        : null;
    final roomId =
        _asString(json['roomId']) ??
        _asString(room?['roomId']) ??
        _asString(room?['id']);
    if (roomId == null) return null;
    return ChatEvent.roomUpdated(roomId: roomId);
  }

  static ChatEvent? _parseUserUpdated(Map<String, dynamic> json) {
    final userId = _asString(json['userId']);
    if (userId == null || userId.isEmpty) return null;
    return ChatEvent.userUpdated(
      userId: userId,
      displayName: _asString(json['displayName']),
      avatarUrl: _asString(json['avatarUrl']),
      // `containsKey` distinguishes "field present and null" (explicit
      // avatar clear) from "field absent" (no change). The backend sets
      // the field whenever it's part of the change set.
      avatarFieldPresent: json.containsKey('avatarUrl'),
      bio: _asString(json['bio']),
      email: _asString(json['email']),
    );
  }

  static ChatEvent? _parseRoomDeleted(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    if (roomId == null) return null;
    // Optional admin-attached metadata. CHT pushes `reason=banned` plus
    // a free-text `adminReason` when a per-room ban is the cause —
    // hosts use these to render an explanatory toast instead of a
    // silent disappearance.
    return ChatEvent.roomDeleted(
      roomId: roomId,
      reason: _asString(json['reason']),
      adminReason: _asString(json['adminReason']),
    );
  }

  static ChatEvent? _parseUserActivity(Map<String, dynamic> json) {
    final userId = _asString(json['userId']) ?? _asString(json['from']);
    if (userId == null) return null;
    final activityStr = _fieldOrDefault(
      json,
      'activity',
      'startsTyping',
      'typing',
    );
    final activity = activityStr == 'stopsTyping'
        ? ChatActivity.stopsTyping
        : ChatActivity.startsTyping;
    final contactId = _asString(json['contactId']);
    if (contactId != null) {
      return ChatEvent.dmActivity(
        contactId: contactId,
        userId: userId,
        activity: activity,
      );
    }
    final roomId = _asString(json['roomId']);
    if (roomId == null) return null;
    return ChatEvent.userActivity(
      roomId: roomId,
      userId: userId,
      activity: activity,
    );
  }

  static ChatEvent? _parsePresenceChanged(Map<String, dynamic> json) {
    final userId = _asString(json['userId']);
    if (userId == null) return null;
    final statusStr = _fieldOrDefault(
      json,
      'status',
      'offline',
      'presence_changed',
    );
    final status = _parsePresenceStatus(statusStr);
    final lastSeenStr = _asString(json['lastSeen']);
    return ChatEvent.presenceChanged(
      userId: userId,
      status: status,
      online: _asBool(json['online']) ?? status != PresenceStatus.offline,
      lastSeen: lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null,
      statusText: _asString(json['statusText']),
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
    final roomId = _asString(json['roomId']);
    if (roomId == null) return null;
    return ChatEvent.unreadUpdated(
      roomId: roomId,
      count: _asInt(json['count']) ?? _asInt(json['unreadMessages']) ?? 0,
    );
  }

  static ChatEvent? _parseUserJoined(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final userId = _asString(json['userId']);
    if (roomId == null || userId == null) return null;
    return ChatEvent.userJoined(roomId: roomId, userId: userId);
  }

  static ChatEvent? _parseUserLeft(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final userId = _asString(json['userId']);
    if (roomId == null || userId == null) return null;
    // `actorUserId` non-null + distinct from `userId` means this
    // was a kick. WhatsApp-parity rendering: the event router
    // synthesises an "Alice removed Bob" system bubble and the
    // kicked client flips `isParticipating=false` so its composer
    // is swapped for the banner. Self-leaves carry no actor.
    final actorUserId = _asString(json['actorUserId']);
    return ChatEvent.userLeft(
      roomId: roomId,
      userId: userId,
      actorUserId: actorUserId,
    );
  }

  static ChatEvent? _parseUserRoleChanged(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final userId = _asString(json['userId']);
    if (roomId == null || userId == null) return null;
    final roleStr = _fieldOrDefault(
      json,
      'role',
      'member',
      'user_role_changed',
    );
    final role = switch (roleStr) {
      'owner' => RoomRole.owner,
      'admin' => RoomRole.admin,
      _ => RoomRole.member,
    };
    return ChatEvent.userRoleChanged(
      roomId: roomId,
      userId: userId,
      role: role,
    );
  }

  static ChatEvent? _parseReceiptUpdated(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final messageId = _asString(json['messageId']);
    if (roomId == null || messageId == null) return null;
    final statusStr = _fieldOrDefault(
      json,
      'status',
      'read',
      'receipt_updated',
    );
    final status = switch (statusStr) {
      'sent' => ReceiptStatus.sent,
      'delivered' => ReceiptStatus.delivered,
      _ => ReceiptStatus.read,
    };
    final fromUserId =
        _asString(json['fromUserId']) ?? _asString(json['userId']);
    return ChatEvent.receiptUpdated(
      roomId: roomId,
      messageId: messageId,
      status: status,
      fromUserId: fromUserId,
    );
  }

  static ChatEvent? _parseMessageAcked(Map<String, dynamic> json) {
    final messageId = _asString(json['messageId']);
    if (messageId == null) return null;
    final seq = json['seq'];
    if (seq is! int) {
      logger?.call(
        'warn',
        'EventParser: "message_acked" event missing integer "seq" field',
      );
      return null;
    }
    final roomId = _asString(json['roomId']);
    final toUserId = _asString(json['toUserId']);
    if (roomId == null && toUserId == null) {
      logger?.call(
        'warn',
        'EventParser: "message_acked" event missing both "roomId" and '
            '"toUserId" fields',
      );
      return null;
    }
    final metadata = json['metadata'];
    return ChatEvent.messageAcked(
      roomId: roomId,
      toUserId: toUserId,
      messageId: messageId,
      seq: seq,
      metadata: metadata is Map<String, dynamic> ? metadata : null,
    );
  }

  static ChatEvent? _parseMessageDelivered(Map<String, dynamic> json) {
    final messageId = _asString(json['messageId']);
    final userId = _asString(json['userId']);
    if (messageId == null || userId == null) return null;
    final seq = json['seq'];
    if (seq is! int) {
      logger?.call(
        'warn',
        'EventParser: "message_delivered" event missing integer "seq" field',
      );
      return null;
    }
    return ChatEvent.messageDelivered(
      roomId: _asString(json['roomId']),
      userId: userId,
      messageId: messageId,
      seq: seq,
    );
  }

  static ChatEvent? _parseReactionAddedNative(Map<String, dynamic> json) {
    final roomId = _asString(json['roomId']);
    final messageId = _asString(json['messageId']);
    final userId = _asString(json['userId']);
    final reaction = _asString(json['emoji']) ?? _asString(json['reaction']);
    if (roomId == null ||
        messageId == null ||
        userId == null ||
        reaction == null) {
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
    final roomId = _asString(json['roomId']);
    final messageId = _asString(json['messageId']);
    if (roomId == null || messageId == null) return null;
    return ChatEvent.reactionDeleted(roomId: roomId, messageId: messageId);
  }

  static ChatEvent? _parseBroadcast(Map<String, dynamic> json) {
    final message = _asString(json['message']);
    if (message == null) return null;
    return ChatEvent.broadcast(
      message: message,
      fromUserId: _asString(json['fromUserId']),
    );
  }

  static String _fieldOrDefault(
    Map<String, dynamic> json,
    String field,
    String defaultValue,
    String eventType,
  ) {
    final value = _asString(json[field]);
    if (value != null) return value;
    logger?.call(
      'warn',
      'EventParser: "$eventType" event missing "$field" field, '
          'defaulting to "$defaultValue"',
    );
    return defaultValue;
  }

  static ChatMessage? _messageFromEvent(Map<String, dynamic> json) {
    final messageData = json['message'] is Map<String, dynamic>
        ? json['message'] as Map<String, dynamic>
        : json;
    final id =
        _asString(messageData['messageId']) ??
        _asString(messageData['idMessage']) ??
        _asString(messageData['id']);
    final from =
        _asString(messageData['from']) ??
        _asString(messageData['userId']) ??
        _asString(json['userId']);
    if (id == null || from == null) return null;
    return MessageMapper.fromJson({
      ...messageData,
      'id': id,
      'from': from,
      'text': messageData['text'] ?? messageData['body'],
      'timestamp':
          messageData['timestamp'] ??
          json['timestamp'] ??
          DateTime.now().toIso8601String(),
    });
  }
}
