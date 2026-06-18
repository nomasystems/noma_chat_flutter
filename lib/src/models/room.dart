import 'package:freezed_annotation/freezed_annotation.dart';

import 'room_user.dart';

part 'room.freezed.dart';

/// A chat room with its basic metadata and member list.
///
/// Equality is id-based so room collections deduplicate by `id` even
/// while metadata (`name`, `subject`, member roster) churns.
@Freezed(equal: false)
abstract class ChatRoom with _$ChatRoom {
  const ChatRoom._();

  const factory ChatRoom({
    required String id,
    String? owner,
    String? name,
    String? subject,
    @Default(RoomAudience.contacts) RoomAudience audience,
    @Default(false) bool allowInvitations,
    @Default(<String>[]) List<String> members,
    String? publicToken,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) = _ChatRoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatRoom && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatRoom($id, $name)';
}

/// Detailed room information including the current user's role and room
/// configuration.
@freezed
abstract class RoomDetail with _$RoomDetail {
  const RoomDetail._();

  const factory RoomDetail({
    required String id,
    String? name,
    String? subject,
    required RoomType type,
    required int memberCount,
    required RoomRole userRole,
    required RoomConfig config,
    @Default(false) bool muted,

    /// When the notification mute expires (UTC). `null` means a permanent
    /// mute (or not muted — check [muted]).
    DateTime? muteUntil,
    @Default(false) bool pinned,
    @Default(false) bool hidden,
    @Default(false) bool selfMuted,
    DateTime? createdAt,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) = _RoomDetail;

  /// True when the composer must be read-only: an announcement channel the
  /// user doesn't own, OR the user has been moderation-muted in this room
  /// (an admin/owner silenced them). [selfMuted] is distinct from [muted]
  /// (the user's own notification preference).
  bool get isReadOnly =>
      (type == RoomType.announcement && userRole != RoomRole.owner) ||
      selfMuted;
}

/// Room-level configuration flags.
@freezed
abstract class RoomConfig with _$RoomConfig {
  const factory RoomConfig({@Default(false) bool allowInvitations}) =
      _RoomConfig;
}

/// The current user's private preferences for a room: notification mute,
/// pin-to-top, and hide-from-list.
///
/// These are per-user and never visible to other members. Returned by
/// [ChatRoomsApi.patchPreferences] as the merged server-side state after a
/// partial update, and embedded in [RoomDetail] for the room info panel.
@freezed
abstract class RoomPreferences with _$RoomPreferences {
  const RoomPreferences._();

  const factory RoomPreferences({
    /// Whether room notifications are silenced. For a timed mute this is
    /// `true` until [muteUntil] passes; the backend derives it server-side.
    @Default(false) bool muted,

    /// Whether the room is pinned to the top of the room list.
    @Default(false) bool pinned,

    /// Whether the room is hidden (WhatsApp-style "archive") from the list.
    @Default(false) bool hidden,

    /// When a timed mute expires (UTC). `null` means a permanent mute (when
    /// [muted] is `true`) or no mute at all (when [muted] is `false`).
    DateTime? muteUntil,
  }) = _RoomPreferences;
}

/// A public room found via discovery search.
@freezed
abstract class DiscoveredRoom with _$DiscoveredRoom {
  const factory DiscoveredRoom({
    required String id,
    String? name,
    String? subject,
    String? owner,
    int? memberCount,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) = _DiscoveredRoom;
}

/// Who can discover and join a room.
///
/// - `public`: anyone can find and join.
/// - `contacts`: only the creator's contacts.
/// - `unrestricted`: invite-only, not listed.
enum RoomAudience { public, contacts, unrestricted }

/// Conversation shape. `oneToOne` rooms hold exactly two users and never
/// promote to a group; `announcement` rooms are read-only for non-admins.
enum RoomType { group, oneToOne, announcement }

/// Behavior for [ChatMembersApi.invite]: invite without joining, accept /
/// decline a pending invitation, or invite-and-join atomically.
enum RoomUserMode { invite, acceptInvitation, declineInvitation, inviteAndJoin }
