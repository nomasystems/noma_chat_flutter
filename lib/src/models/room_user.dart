import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_user.freezed.dart';

/// Optional resource expansions for [ChatMembersApi.list].
///
/// Pass via the `expand` param to ask the backend to embed extra fields in
/// each member row instead of returning the bare `{userId, role}`. The wire
/// value is the lowercase enum name, sent as the `expand` query param
/// (e.g. `?expand=users`).
enum RoomMemberExpand {
  /// Embed the member's `displayName` + `avatarUrl` in every row, so a group
  /// roster renders names and avatars from a single `list` call — no
  /// per-member `GET /users/{id}` round-trip (the N+1 it eliminates).
  users;

  String toJson() => name;
}

/// Room-level role. The backend wire format uses "user" for [member].
enum RoomRole {
  owner,
  admin,
  member;

  String toJson() => switch (this) {
    RoomRole.member => 'user',
    _ => name,
  };
}

/// A member of a room with their assigned role.
///
/// Equality is id-based on [userId] so a `Set<RoomUser>` deduplicates by
/// user regardless of role transitions during a single render pass.
///
/// [displayName] and [avatarUrl] are populated only when the member list is
/// fetched with the `users` expansion (see [ChatMembersApi.list]'s `expand`
/// param). Without expansion the backend emits just `{userId, role}` and both
/// stay `null` — render group members by resolving the id through the user
/// cache as before. With expansion they let consumers render the roster
/// (names + avatars) straight from the list response, with no per-member
/// `GET /users/{id}` round-trip (the N+1 the expansion eliminates).
@Freezed(equal: false)
abstract class RoomUser with _$RoomUser {
  const RoomUser._();

  const factory RoomUser({
    required String userId,
    @Default(RoomRole.member) RoomRole role,

    /// Member display name. Non-null only on an expanded list response.
    String? displayName,

    /// Member avatar URL. Non-null only on an expanded list response.
    String? avatarUrl,
  }) = _RoomUser;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RoomUser && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}
