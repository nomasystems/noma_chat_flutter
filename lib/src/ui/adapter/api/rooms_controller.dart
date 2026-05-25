part of '../chat_ui_adapter.dart';

/// Room-level operations exposed by [ChatUiAdapter.rooms].
///
/// Covers list bootstrap (`load`), membership flags
/// (`mute`/`unmute`, `pin`/`unpin`, `hide`/`unhide`), invitation
/// lifecycle (`acceptInvitation` / `rejectInvitation`,
/// `deleteKicked`), room metadata (`updateConfig`), member management
/// (`addMembers`, `removeMember`, `updateMemberRole`), group creation
/// (`createGroup`) and the exit path (`leave`).
final class ChatRoomsController {
  ChatRoomsController(this._a);

  final ChatUiAdapter _a;

  /// Refreshes the room list (cache-then-network).
  Future<ChatResult<void>> load({
    String type = 'all',
    bool forceNetwork = false,
  }) {
    // Dedupe concurrent calls via the lifecycle's completer slot —
    // a second load while one is in flight returns the same Future.
    final existing = _a._lifecycle.pendingLoadRooms;
    if (existing != null) return existing.future;
    final completer = Completer<ChatResult<void>>();
    _a._lifecycle.pendingLoadRooms = completer;
    _a
        ._doLoadRooms(type: type, forceNetwork: forceNetwork)
        .then(
          (result) => completer.complete(
            _a._emitFailure(result, OperationKind.loadRooms),
          ),
          onError: (Object e) {
            final result = ChatFailureResult<void>(
              NetworkFailure(e.toString()),
            );
            _a._emitFailure(result, OperationKind.loadRooms);
            completer.complete(result);
          },
        )
        .whenComplete(() => _a._lifecycle.pendingLoadRooms = null);
    return completer.future;
  }

  /// Mutes [roomId] (optimistic).
  Future<ChatResult<void>> mute(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(muted: v),
    true,
    _a.client.rooms.mute,
    OperationKind.muteRoom,
  );

  /// Reverts a mute on [roomId].
  Future<ChatResult<void>> unmute(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(muted: v),
    false,
    _a.client.rooms.unmute,
    OperationKind.unmuteRoom,
  );

  /// Pins [roomId] to the top of the room list.
  Future<ChatResult<void>> pin(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(pinned: v),
    true,
    _a.client.rooms.pin,
    OperationKind.pinRoom,
  );

  /// Removes the pin from [roomId].
  Future<ChatResult<void>> unpin(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(pinned: v),
    false,
    _a.client.rooms.unpin,
    OperationKind.unpinRoom,
  );

  /// Hides [roomId] from the user's room list.
  Future<ChatResult<void>> hide(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(hidden: v),
    true,
    _a.client.rooms.hide,
    OperationKind.hideRoom,
  );

  /// Reveals a previously hidden [roomId].
  Future<ChatResult<void>> unhide(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(hidden: v),
    false,
    _a.client.rooms.unhide,
    OperationKind.unhideRoom,
  );

  /// Removes the current user from [roomId].
  Future<ChatResult<void>> leave(String roomId) async {
    final result = await _a.client.members.leave(roomId);
    if (result.isSuccess) {
      _a.roomListController.removeRoom(roomId);
      _a.removeChatController(roomId);
    }
    return _a._emitFailure(result, OperationKind.leaveRoom, roomId: roomId);
  }

  /// Patches [roomId]'s metadata. Pass `clearAvatar: true` to remove
  /// the avatar of the room (mutually exclusive with a non-null
  /// `avatarUrl`); the SDK forwards an empty string so the backend's
  /// `apply_room_config` overwrites the preserved value with "" instead
  /// of restoring the previous one.
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar = false,
    Map<String, dynamic>? custom,
  }) async {
    final result = await _a.client.rooms.updateConfig(
      roomId,
      name: name,
      subject: subject,
      avatarUrl: avatarUrl,
      clearAvatar: clearAvatar,
      custom: custom,
    );
    return _a._emitFailure(
      result,
      OperationKind.updateRoomConfig,
      roomId: roomId,
    );
  }

  /// Accepts a pending invitation to [roomId].
  Future<ChatResult<void>> acceptInvitation(String roomId) async {
    final result = await _a.client.members.invite(
      roomId,
      userIds: [_a.currentUser.id],
      mode: RoomUserMode.acceptInvitation,
    );
    if (result.isSuccess) {
      final existing = _a.roomListController.getRoomById(roomId);
      if (existing != null) {
        final custom = Map<String, dynamic>.from(existing.custom ?? {});
        custom.remove('invited');
        custom.remove('invitedBy');
        _a.roomListController.updateRoom(
          existing.copyWith(
            custom: custom.isEmpty ? null : custom,
            userRole: RoomRole.member,
          ),
        );
      }
    }
    return _a._emitFailure(
      result,
      OperationKind.acceptInvitation,
      roomId: roomId,
    );
  }

  /// Rejects a pending invitation to [roomId].
  Future<ChatResult<void>> rejectInvitation(String roomId) async {
    final previous = _a.roomListController.getRoomById(roomId);
    _a.roomListController.removeRoom(roomId);
    final result = await _a.client.members.leave(roomId);
    if (result.isFailure && previous != null && !_a._disposed) {
      _a.roomListController.addRoom(previous);
    }
    return _a._emitFailure(
      result,
      OperationKind.rejectInvitation,
      roomId: roomId,
    );
  }

  /// Invites [userIds] to [roomId].
  Future<ChatResult<void>> addMembers(
    String roomId,
    List<String> userIds, {
    RoomUserMode mode = RoomUserMode.inviteAndJoin,
  }) async {
    final result = await _a.client.members.invite(
      roomId,
      userIds: userIds,
      mode: mode,
    );
    return _a._emitFailure(result, OperationKind.addMembers, roomId: roomId);
  }

  /// Removes [userId] from [roomId].
  Future<ChatResult<void>> removeMember(String roomId, String userId) async {
    final result = await _a.client.members.remove(roomId, userId);
    return _a._emitFailure(
      result,
      OperationKind.removeMember,
      roomId: roomId,
      userId: userId,
    );
  }

  /// Promotes / demotes [userId] in [roomId].
  Future<ChatResult<void>> updateMemberRole(
    String roomId,
    String userId,
    RoomRole role,
  ) async {
    final result = await _a.client.members.updateRole(roomId, userId, role);
    return _a._emitFailure(
      result,
      OperationKind.updateMemberRole,
      roomId: roomId,
      userId: userId,
    );
  }

  /// Creates a new group room.
  Future<ChatResult<String>> createGroup({
    required String name,
    required List<String> memberIds,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    String? subject,
    bool allowInvitations = false,
    RoomAudience audience = RoomAudience.contacts,
    Map<String, dynamic>? custom,
  }) async {
    String? avatarUrl;
    if (avatarBytes != null && avatarMimeType != null) {
      final uploadRes = await _a.uploadAvatar(
        avatarBytes,
        avatarMimeType,
        AvatarKind.room,
      );
      if (uploadRes.isFailure) {
        return _a._emitFailure(
          uploadRes.castFailure<String>(),
          OperationKind.createGroupRoom,
        );
      }
      avatarUrl = uploadRes.dataOrNull;
    }
    final createRes = await _a.client.rooms.create(
      audience: audience,
      allowInvitations: allowInvitations,
      members: memberIds,
      name: name,
      subject: subject,
      avatarUrl: avatarUrl,
      custom: custom,
    );
    if (createRes.isFailure) {
      return _a._emitFailure(
        createRes.castFailure<String>(),
        OperationKind.createGroupRoom,
      );
    }
    final room = createRes.dataOrNull;
    if (room == null || room.id.isEmpty) {
      return _a._emitFailure(
        const ChatFailureResult<String>(
          UnexpectedFailure('create room returned empty id'),
        ),
        OperationKind.createGroupRoom,
      );
    }
    // Refresh the room list so the new entry surfaces immediately rather
    // than waiting for the `room_created` WS echo.
    unawaited(load());
    return ChatSuccess(room.id);
  }

  /// Drops [roomId] locally after the backend signalled the current
  /// user was removed (kicked / banned).
  Future<void> deleteKicked(String roomId) =>
      _a._memberEventHandler.deleteKickedChat(roomId);
}
