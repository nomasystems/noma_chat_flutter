import 'package:freezed_annotation/freezed_annotation.dart';

import 'message.dart';
import 'room.dart' show RoomWritePolicy;
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

    /// Text of the last message as its sender wrote it. Never a label or a
    /// sentence composed by the SDK — it feeds `RoomListItem.lastMessage`
    /// on rehydration, and the room-list preview is built from there at
    /// paint time.
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    @Default(false) bool lastMessageIsDeleted,

    /// `true` when the last message is a system notice rather than something
    /// a person wrote. Feeds `RoomListItem.lastMessageIsSystem` on
    /// rehydration so the row keeps dropping the sender prefix across
    /// restarts.
    @Default(false) bool lastMessageIsSystem,
    String? lastMessageReactionEmoji,

    /// Text of the message the last reaction was aimed at, truncated to 30
    /// grapheme clusters, quoted inside the reaction preview.
    String? lastMessageReactionTargetText,

    /// Type of the message the last reaction was aimed at, so a text-less
    /// one can be quoted by its label in the reader's own language.
    MessageType? lastMessageReactionTargetType,
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

    /// Who may post into this room, as the listing projection reports it in
    /// `config.writePolicy`. Mirrors the room detail's own policy so the
    /// list can hide the composer of an owner-only room without waiting for
    /// a per-room detail fetch, and keeps it across a cold start from cache.
    /// A backend that does not emit the field leaves it at
    /// [RoomWritePolicy.members].
    @Default(RoomWritePolicy.members) RoomWritePolicy writePolicy,
  }) = _UnreadRoom;
}
