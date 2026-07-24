import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/message.dart';
import '../../models/presence.dart';
import '../../models/room_user.dart';

part 'room_list_item.freezed.dart';

/// View model for a row in the room list, combining server-side room
/// metadata with client-side state (unread, presence, typing, etc.).
///
/// Value-typed: every field participates in equality so a
/// `ListenableBuilder` listening to a `roomListController.value` rebuilds
/// when any visible attribute changes (badge, preview, presence dot...).
@freezed
abstract class RoomListItem with _$RoomListItem {
  const RoomListItem._();

  const factory RoomListItem({
    required String id,
    String? name,
    String? subject,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,

    /// Display name of [lastMessageUserId], resolved by the adapter from
    /// its user cache when available. Lets the chat list show the WhatsApp
    /// "Alice: hola" prefix in groups without the consumer wiring its own
    /// name resolver. `null` when the sender is the current user, when
    /// `lastMessageUserId` is null, or when the user has not been fetched
    /// yet — in that last case the adapter refreshes the row as soon as
    /// the user lands in the cache (typically within a few hundred ms of
    /// the first room load).
    String? lastMessageSenderName,
    String? lastMessageId,
    ReceiptStatus? lastMessageReceipt,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    @Default(false) bool lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
    @Default(0) int unreadCount,

    /// Count of unread messages in this room that mention the current user.
    /// Drives the "@" badge on the tile. `0` when none.
    @Default(0) int unreadMentions,
    @Default(false) bool muted,

    /// When the notification mute expires (UTC). `null` means a permanent
    /// mute (or not muted — check [muted]).
    DateTime? muteUntil,
    @Default(false) bool pinned,
    @Default(false) bool hidden,

    /// Moderation mute: an admin/owner silenced the current user in this
    /// room (distinct from [muted] = the user's own notification
    /// preference). Drives the read-only composer via [isReadOnly].
    @Default(false) bool selfMuted,
    @Default(false) bool isGroup,
    @Default(false) bool isAnnouncement,
    bool? isOnline,
    PresenceStatus? presenceStatus,

    /// Wall-clock time the other 1:1 participant was last seen online,
    /// mirroring [ChatPresence.lastSeen]. `null` when unknown (group rooms,
    /// no presence event/bootstrap has landed yet, or the peer has never
    /// gone offline since the app connected). Drives the "last seen …"
    /// subtitle in [ChatRoomAppBar] when [isOnline] is `false`.
    DateTime? lastSeen,
    String? otherUserId,
    RoomRole? userRole,
    int? memberCount,
    Map<String, dynamic>? custom,
    @Default(<String>{}) Set<String> typingUserIds,

    /// Title computed by the adapter via the configured `RoomTitleResolver` or
    /// the SDK's DM-aware default (for one-to-one rooms, the other member's
    /// `displayName`). Kept separate from [name] so the server-provided room
    /// name remains intact and consumers can fall back to it (e.g. in tests or
    /// during enrichment races where the other member has not been resolved
    /// yet). `null` means the SDK has not produced an effective title for this
    /// row.
    String? effectiveDisplayName,

    /// `false` when the local user has been removed from this room by
    /// an admin kick — WhatsApp-parity. The chat stays in the list
    /// with full history, but the composer is swapped for the
    /// "You are no longer a participant" banner (see
    /// `ChatView.isParticipating`). Set to `false` by the event router
    /// when a `user_left` event arrives with `actorUserId != userId &&
    /// userId == me`, and flipped back to `true` when the admin
    /// re-adds the user via `user_joined`.
    @Default(true) bool isParticipating,
  }) = _RoomListItem;

  /// User-facing label for the row. Resolves in this order:
  /// 1. [effectiveDisplayName] (set by the adapter — custom resolver result
  ///    or DM-aware default).
  /// 2. [name] when non-empty.
  /// 3. Empty string. We deliberately do NOT fall back to [id] (a UUID)
  ///    because exposing an opaque server identifier as a chat title is
  ///    actively worse than blank space (it confuses users and looks like
  ///    a bug). Consumers that want a placeholder should render their own
  ///    fallback string when [displayName] is empty.
  String get displayName {
    final eff = effectiveDisplayName?.trim();
    if (eff != null && eff.isNotEmpty) return eff;
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '';
  }

  bool get isInvitation => custom?['invited'] == true;

  /// Composer must be read-only when this is an announcement channel the
  /// user doesn't own, OR the user has been moderation-muted here.
  bool get isReadOnly =>
      (isAnnouncement && userRole != RoomRole.owner) || selfMuted;
}
