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

    /// Count of unread messages in this room that mention the current user.
    /// `0` when there are none. Drives the "@" badge on the room tile
    /// without fetching message bodies.
    @Default(0) int unreadMentions,
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

    /// When the notification mute expires (UTC). `null` means a permanent
    /// mute (or not muted at all — check [muted]). Lets the UI show "muted
    /// until 14:00" and the consumer re-derive [muted] after expiry.
    DateTime? muteUntil,
    @Default(false) bool pinned,
    @Default(false) bool hidden,
    @Default(false) bool selfMuted,
  }) = _UnreadRoom;
}
