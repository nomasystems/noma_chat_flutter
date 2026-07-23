import '../../models/message.dart';
import '../../models/room.dart';
import '../../models/room_user.dart';
import '../../models/user_rooms.dart';
import '../../models/unread_room.dart';
import '../../models/invited_room.dart';
import '../dto/room_dto.dart';
import '../util/json_safe.dart';

class RoomMapper {
  static ChatRoom fromDto(RoomDto dto) => ChatRoom(
    id: dto.roomId,
    owner: dto.owner,
    name: dto.name,
    subject: dto.subject,
    audience: _parseAudience(dto.audience),
    allowInvitations: dto.allowInvitations ?? false,
    members: dto.members ?? [],
    publicToken: dto.publicToken,
    avatarUrl: dto.avatarUrl,
    custom: dto.custom,
  );

  static ChatRoom fromJson(Map<String, dynamic> json) =>
      fromDto(RoomDto.fromJson(json));

  static RoomDetail detailFromDto(RoomDetailDto dto) => RoomDetail(
    id: dto.id,
    name: dto.name,
    subject: dto.subject,
    type: switch (dto.type) {
      'one-to-one' => RoomType.oneToOne,
      'announcement' => RoomType.announcement,
      _ => RoomType.group,
    },
    memberCount: dto.memberCount,
    userRole: _parseRoomRole(dto.userRole),
    config: RoomConfig(
      allowInvitations: jsonBoolOr(dto.config?['allowInvitations'], false),
    ),
    muted: dto.muted,
    muteUntil: dto.muteUntil != null ? DateTime.tryParse(dto.muteUntil!) : null,
    pinned: dto.pinned,
    hidden: dto.hidden,
    selfMuted: dto.selfMuted,
    createdAt: dto.createdAt != null ? DateTime.tryParse(dto.createdAt!) : null,
    avatarUrl: dto.avatarUrl,
    custom: dto.custom,
  );

  static RoomDetail detailFromJson(Map<String, dynamic> json) =>
      detailFromDto(RoomDetailDto.fromJson(json));

  /// Parses the `200` body of `PATCH /rooms/{id}/preferences`:
  /// `{muted, pinned, hidden, muteUntil?}`. `muteUntil` may be absent or a
  /// non-string when not a timed mute.
  static RoomPreferences preferencesFromJson(Map<String, dynamic> json) =>
      RoomPreferences(
        muted: jsonBoolOr(json['muted'], false),
        pinned: jsonBoolOr(json['pinned'], false),
        hidden: jsonBoolOr(json['hidden'], false),
        muteUntil: json['muteUntil'] is String
            ? DateTime.tryParse(json['muteUntil'] as String)
            : null,
      );

  static DiscoveredRoom discoveredFromJson(Map<String, dynamic> json) =>
      DiscoveredRoom(
        id: jsonIdOr(json['roomId'] ?? json['id'], ''),
        name: jsonStringOrNull(json['name']),
        subject: jsonStringOrNull(json['subject']),
        owner: jsonStringOrNull(json['owner']),
        memberCount: jsonIntOrNull(json['memberCount']),
        avatarUrl: jsonStringOrNull(json['avatarUrl']),
        custom: jsonMapOrNull(json['custom']),
      );

  static UserRooms userRoomsFromDto(UserRoomsDto dto) => UserRooms(
    rooms: dto.rooms.map(unreadRoomFromJson).toList(),
    invitedRooms: dto.invitedRooms.map(_invitedRoomFromJson).toList(),
    hasMore: dto.hasMore,
  );

  static UserRooms userRoomsFromJson(Map<String, dynamic> json) =>
      userRoomsFromDto(UserRoomsDto.fromJson(json));

  static UnreadRoom unreadRoomFromJson(Map<String, dynamic> json) {
    // `lastUnreadMessage` is an object when the room has an unread preview, or
    // `null`/absent when there is none. Anything that is not a JSON object is
    // treated as "no unread" — all preview fields stay null.
    final lastMsg = json['lastUnreadMessage'];
    String? lastMessage;
    DateTime? lastMessageTime;
    String? lastMessageUserId;
    String? lastMessageId;
    MessageType? lastMessageType;
    String? lastMessageMimeType;
    String? lastMessageFileName;
    int? lastMessageDurationMs;
    bool lastMessageIsDeleted = false;
    String? lastMessageReactionEmoji;
    ReceiptStatus? lastMessageReceipt;

    if (lastMsg is Map<String, dynamic>) {
      lastMessage = _asString(lastMsg['body']) ?? _asString(lastMsg['text']);
      final ts = _asString(lastMsg['timestamp']);
      lastMessageTime = ts != null ? DateTime.tryParse(ts) : null;
      // `from` is the canonical sender id.
      lastMessageUserId = _asString(lastMsg['from']);
      lastMessageId =
          _asString(lastMsg['messageId']) ?? _asString(lastMsg['id']);
      lastMessageType = _parseMessageTypeNullable(
        _asString(lastMsg['messageType']),
      );
      lastMessageMimeType =
          _asString(lastMsg['mimeType']) ?? _asString(lastMsg['mime_type']);
      lastMessageFileName =
          _asString(lastMsg['fileName']) ?? _asString(lastMsg['file_name']);
      final meta = lastMsg['metadata'];
      if (meta is Map<String, dynamic>) {
        final dur = meta['duration'];
        if (dur is num) lastMessageDurationMs = dur.toInt();
        lastMessageMimeType ??= _asString(meta['mimeType']);
      }
      lastMessageIsDeleted = jsonBoolOr(lastMsg['isDeleted'], false);
      lastMessageReactionEmoji = _parseReactionEmoji(lastMsg['reaction']);
      lastMessageReceipt = _parseReceiptStatus(_asString(lastMsg['receipt']));
    }

    if ((lastMessageType == null || lastMessageType == MessageType.regular) &&
        ((lastMessageMimeType != null && lastMessageMimeType.isNotEmpty) ||
            (lastMessageFileName != null && lastMessageFileName.isNotEmpty))) {
      lastMessageType = MessageType.attachment;
    }

    return UnreadRoom(
      roomId: jsonIdOr(json['roomId'], ''),
      unreadMessages: jsonIntOr(json['unreadMessages'], 0),
      unreadMentions: jsonIntOr(json['unreadMentions'], 0),
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      lastMessageUserId: lastMessageUserId,
      lastMessageId: lastMessageId,
      lastMessageType: lastMessageType,
      lastMessageMimeType: lastMessageMimeType,
      lastMessageFileName: lastMessageFileName,
      lastMessageDurationMs: lastMessageDurationMs,
      lastMessageIsDeleted: lastMessageIsDeleted,
      lastMessageReactionEmoji: lastMessageReactionEmoji,
      lastMessageReceipt: lastMessageReceipt,
      name: jsonStringOrNull(json['name']),
      avatarUrl: jsonStringOrNull(json['avatarUrl']),
      type: jsonStringOrNull(json['type']),
      memberCount: jsonIntOrNull(json['memberCount']),
      userRole: _parseRoomRoleNullable(jsonStringOrNull(json['userRole'])),
      muted: jsonBoolOr(json['muted'], false),
      muteUntil: json['muteUntil'] is String
          ? DateTime.tryParse(json['muteUntil'] as String)
          : null,
      pinned: jsonBoolOr(json['pinned'], false),
      hidden: jsonBoolOr(json['hidden'], false),
      selfMuted: jsonBoolOr(json['selfMuted'], false),
    );
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static MessageType? _parseMessageTypeNullable(String? type) => switch (type) {
    'attachment' => MessageType.attachment,
    'reaction' => MessageType.reaction,
    'reply' => MessageType.reply,
    'audio' => MessageType.audio,
    'forward' => MessageType.forward,
    'location' => MessageType.location,
    'regular' => MessageType.regular,
    _ => null,
  };

  /// Extracts a preview emoji from the `reaction` field of a last-unread
  /// message. The backend ships an array of `ReactionSummary`
  /// (`{from, reaction, time}`); the legacy/local cache path may ship a
  /// plain string. Returns the last reaction's emoji for a list (most
  /// recent), the value itself for a string, or null otherwise.
  static String? _parseReactionEmoji(Object? raw) {
    if (raw is String) return raw;
    if (raw is List && raw.isNotEmpty) {
      final last = raw.last;
      if (last is Map) {
        return _asString(last['reaction']) ?? _asString(last['emoji']);
      }
    }
    return null;
  }

  static ReceiptStatus? _parseReceiptStatus(String? value) => switch (value) {
    'sent' => ReceiptStatus.sent,
    'delivered' => ReceiptStatus.delivered,
    'read' => ReceiptStatus.read,
    _ => null,
  };

  static InvitedRoom _invitedRoomFromJson(Map<String, dynamic> json) =>
      InvitedRoom(
        roomId: jsonIdOr(json['roomId'], ''),
        invitedBy: jsonIdOr(json['invitedBy'], ''),
        roomName: jsonStringOrNull(json['roomName']),
        subject: jsonStringOrNull(json['subject']),
        roomType: jsonStringOrNull(json['roomType']),
      );

  static RoomAudience _parseAudience(String? audience) => switch (audience) {
    'public' => RoomAudience.public,
    'unrestricted' => RoomAudience.unrestricted,
    _ => RoomAudience.contacts,
  };

  static RoomRole _parseRoomRole(String? role) => switch (role) {
    'owner' => RoomRole.owner,
    'admin' => RoomRole.admin,
    _ => RoomRole.member,
  };

  static RoomRole? _parseRoomRoleNullable(String? role) => switch (role) {
    'owner' => RoomRole.owner,
    'admin' => RoomRole.admin,
    'user' || 'member' => RoomRole.member,
    _ => null,
  };
}
