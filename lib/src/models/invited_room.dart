import 'package:freezed_annotation/freezed_annotation.dart';

part 'invited_room.freezed.dart';

/// A pending room invitation showing who invited the current user.
///
/// Equality is id-based on [roomId] so the same invitation never appears
/// twice in a [Set<InvitedRoom>] even if [invitedBy] races between
/// duplicate notifications.
@Freezed(equal: false)
abstract class InvitedRoom with _$InvitedRoom {
  const InvitedRoom._();

  const factory InvitedRoom({
    required String roomId,
    required String invitedBy,
  }) = _InvitedRoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InvitedRoom && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;
}
