import 'message.dart';
import 'room_user.dart';

/// A room with its unread count and last message preview.
class UnreadRoom {
  final String roomId;
  final int unreadMessages;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? lastMessageUserId;
  final String? lastMessageId;
  final MessageType? lastMessageType;
  final String? lastMessageMimeType;
  final String? lastMessageFileName;
  final int? lastMessageDurationMs;
  final bool lastMessageIsDeleted;
  final String? lastMessageReactionEmoji;
  final String? name;
  final String? avatarUrl;
  final String? type;
  final int? memberCount;
  final RoomRole? userRole;
  final bool muted;
  final bool pinned;
  final bool hidden;

  const UnreadRoom({
    required this.roomId,
    required this.unreadMessages,
    this.lastMessage,
    this.lastMessageTime,
    this.lastMessageUserId,
    this.lastMessageId,
    this.lastMessageType,
    this.lastMessageMimeType,
    this.lastMessageFileName,
    this.lastMessageDurationMs,
    this.lastMessageIsDeleted = false,
    this.lastMessageReactionEmoji,
    this.name,
    this.avatarUrl,
    this.type,
    this.memberCount,
    this.userRole,
    this.muted = false,
    this.pinned = false,
    this.hidden = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UnreadRoom && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;
}
