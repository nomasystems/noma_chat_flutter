import 'package:freezed_annotation/freezed_annotation.dart';

import 'invited_room.dart';
import 'unread_room.dart';

part 'user_rooms.freezed.dart';

/// The current user's rooms and pending invitations.
@freezed
abstract class UserRooms with _$UserRooms {
  const factory UserRooms({
    required List<UnreadRoom> rooms,
    @Default(<InvitedRoom>[]) List<InvitedRoom> invitedRooms,
    @Default(false) bool hasMore,
  }) = _UserRooms;
}
