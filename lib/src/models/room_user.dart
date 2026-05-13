import 'package:flutter/foundation.dart';

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
@immutable
class RoomUser {
  final String userId;
  final RoomRole role;

  const RoomUser({required this.userId, this.role = RoomRole.member});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RoomUser && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}
