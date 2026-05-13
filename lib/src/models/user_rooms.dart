import 'unread_room.dart';
import 'invited_room.dart';

/// The current user's rooms and pending invitations.
class UserRooms {
  final List<UnreadRoom> rooms;
  final List<InvitedRoom> invitedRooms;
  final bool hasMore;

  const UserRooms({
    required this.rooms,
    this.invitedRooms = const [],
    this.hasMore = false,
  });
}
