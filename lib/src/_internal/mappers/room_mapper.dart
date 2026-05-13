import '../../models/message.dart';
import '../../models/room.dart';
import '../../models/room_user.dart';
import '../../models/user_rooms.dart';
import '../../models/unread_room.dart';
import '../../models/invited_room.dart';
import '../dto/room_dto.dart';

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
          allowInvitations:
              dto.config?['allowInvitations'] as bool? ?? false,
        ),
        muted: dto.muted,
        pinned: dto.pinned,
        hidden: dto.hidden,
        createdAt:
            dto.createdAt != null ? DateTime.tryParse(dto.createdAt!) : null,
        avatarUrl: dto.avatarUrl,
        custom: dto.custom,
      );

  static RoomDetail detailFromJson(Map<String, dynamic> json) =>
      detailFromDto(RoomDetailDto.fromJson(json));

  static DiscoveredRoom discoveredFromJson(Map<String, dynamic> json) =>
      DiscoveredRoom(
        id: (json['roomId'] ?? json['id'] ?? '') as String,
        name: json['name'] as String?,
        subject: json['subject'] as String?,
        owner: json['owner'] as String?,
        memberCount: json['memberCount'] as int?,
        avatarUrl: json['avatarUrl'] as String?,
        custom: json['custom'] as Map<String, dynamic>?,
      );

  static UserRooms userRoomsFromDto(UserRoomsDto dto) => UserRooms(
        rooms: dto.rooms.map(unreadRoomFromJson).toList(),
        invitedRooms: dto.invitedRooms.map(_invitedRoomFromJson).toList(),
        hasMore: dto.hasMore,
      );

  static UserRooms userRoomsFromJson(Map<String, dynamic> json) =>
      userRoomsFromDto(UserRoomsDto.fromJson(json));

  static UnreadRoom unreadRoomFromJson(Map<String, dynamic> json) {
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

    if (lastMsg is Map<String, dynamic>) {
      lastMessage = _asString(lastMsg['body']) ?? _asString(lastMsg['text']);
      final ts = _asString(lastMsg['timestamp']);
      lastMessageTime = ts != null ? DateTime.tryParse(ts) : null;
      lastMessageUserId =
          _asString(lastMsg['fromJid']) ?? _asString(lastMsg['from']);
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
      lastMessageIsDeleted = (lastMsg['isDeleted'] as bool?) ?? false;
      lastMessageReactionEmoji = _asString(lastMsg['reaction']);
    } else {
      lastMessage = json['lastMessage'] as String?;
      final ts = json['lastMessageTime'] as String?;
      lastMessageTime = ts != null ? DateTime.tryParse(ts) : null;
      lastMessageUserId = json['lastMessageUserId'] as String?;
      lastMessageId = json['lastMessageId'] as String?;
      lastMessageType = _parseMessageTypeNullable(
        json['lastMessageType'] as String?,
      );
      lastMessageMimeType = json['lastMessageMimeType'] as String?;
      lastMessageFileName = json['lastMessageFileName'] as String?;
      final dur = json['lastMessageDurationMs'];
      if (dur is num) lastMessageDurationMs = dur.toInt();
      lastMessageIsDeleted = (json['lastMessageIsDeleted'] as bool?) ?? false;
      lastMessageReactionEmoji = json['lastMessageReactionEmoji'] as String?;
    }

    return UnreadRoom(
      roomId: (json['roomId'] ?? '') as String,
      unreadMessages: (json['unreadMessages'] ?? 0) as int,
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
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      type: json['type'] as String?,
      memberCount: json['memberCount'] as int?,
      userRole: _parseRoomRoleNullable(json['userRole'] as String?),
      muted: (json['muted'] ?? false) as bool,
      pinned: (json['pinned'] ?? false) as bool,
      hidden: (json['hidden'] ?? false) as bool,
    );
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static MessageType? _parseMessageTypeNullable(String? type) =>
      switch (type) {
        'attachment' => MessageType.attachment,
        'reaction' => MessageType.reaction,
        'reply' => MessageType.reply,
        'audio' => MessageType.audio,
        'forward' => MessageType.forward,
        'regular' => MessageType.regular,
        _ => null,
      };

  static InvitedRoom _invitedRoomFromJson(Map<String, dynamic> json) =>
      InvitedRoom(
        roomId: (json['roomId'] ?? '') as String,
        invitedBy: (json['invitedBy'] ?? '') as String,
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
