import 'package:freezed_annotation/freezed_annotation.dart';

import 'message.dart';
import 'room_user.dart';

part 'unread_room.freezed.dart';

/// A room with its unread count and last message preview.
///
/// Value-typed: equality and `hashCode` consider every field, so two
/// instances with the same `roomId` but different `unreadMessages` /
/// `lastMessage` / etc. compare unequal. Without this, a `ListenableBuilder`
/// listening to a `roomListController.value` would skip rebuilds when
/// only the badge or preview changed.
@freezed
abstract class UnreadRoom with _$UnreadRoom {
  const factory UnreadRoom({
    required String roomId,
    required int unreadMessages,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    @Default(false) bool lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
    ReceiptStatus? lastMessageReceipt,
    String? name,
    String? avatarUrl,
    String? type,
    int? memberCount,
    RoomRole? userRole,
    @Default(false) bool muted,
    @Default(false) bool pinned,
    @Default(false) bool hidden,
  }) = _UnreadRoom;
}
