import 'package:flutter/foundation.dart';

/// A pending room invitation showing who invited the current user.
@immutable
class InvitedRoom {
  final String roomId;
  final String invitedBy;

  const InvitedRoom({required this.roomId, required this.invitedBy});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InvitedRoom && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;
}
