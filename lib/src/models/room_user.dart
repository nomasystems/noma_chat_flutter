import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_user.freezed.dart';

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
@Freezed(equal: false)
abstract class RoomUser with _$RoomUser {
  const RoomUser._();

  const factory RoomUser({
    required String userId,
    @Default(RoomRole.member) RoomRole role,
  }) = _RoomUser;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RoomUser && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}
