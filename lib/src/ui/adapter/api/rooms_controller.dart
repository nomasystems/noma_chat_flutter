part of '../chat_ui_adapter.dart';

/// Room-level operations exposed by [ChatUiAdapter.rooms].
///
/// Covers list bootstrap (`load`), membership flags
/// (`mute`/`unmute`, `pin`/`unpin`), archive (`hide`/`unhide` /
/// `unarchive`), per-user delete (`delete`), invitation
/// lifecycle (`acceptInvitation` / `rejectInvitation`,
/// `deleteKicked`), room metadata (`updateConfig`), member management
/// (`addMembers`, `removeMember`, `updateMemberRole`), group creation
/// (`createGroup`) and the exit path (`leave`).
final class ChatRoomsController {
  ChatRoomsController(this._a);

  final ChatUiAdapter _a;

  /// Refreshes the room list (cache-then-network).
  ///
  /// A successful network pass is always authoritative for the caller's
  /// complete room set — see [ChatUiAdapter.loadRooms] for the full
  /// rationale. A failed one (network error, timeout, 5xx) never touches
  /// the list.
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

  /// Mutes [roomId] (optimistic). Pass [until] for a timed mute
  /// (WhatsApp-style 8h / 1 week); omit it for a permanent mute. The room
  /// tile reflects [RoomListItem.muteUntil] until the next list refresh.
  Future<ChatResult<void>> mute(String roomId, {DateTime? until}) async {
    final room = _a.roomListController.getRoomById(roomId);
    if (room != null) {
      _a.roomListController.updateRoom(
        room.copyWith(muted: true, muteUntil: until),
      );
    }
    final result = await _a.client.rooms
        .patchPreferences(
          roomId,
          muted: until == null ? true : null,
          muteUntil: until,
        )
        .discardValue();
    if (result.isFailure && room != null) {
      _a.roomListController.updateRoom(room);
    }
    return _a._emitFailure(result, OperationKind.muteRoom, roomId: roomId);
  }

  /// Reverts a mute on [roomId], clearing any timed-mute expiry.
  Future<ChatResult<void>> unmute(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(muted: v, muteUntil: v ? r.muteUntil : null),
    false,
    (id) => _a.client.rooms.patchPreferences(id, muted: false).discardValue(),
    OperationKind.unmuteRoom,
  );

  /// Pins [roomId] to the top of the room list.
  Future<ChatResult<void>> pin(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(pinned: v),
    true,
    (id) => _a.client.rooms.patchPreferences(id, pinned: true).discardValue(),
    OperationKind.pinRoom,
  );

  /// Removes the pin from [roomId].
  Future<ChatResult<void>> unpin(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(pinned: v),
    false,
    (id) => _a.client.rooms.patchPreferences(id, pinned: false).discardValue(),
    OperationKind.unpinRoom,
  );

  /// ARCHIVE — moves [roomId] into the collapsible "Archived" section of
  /// the room list (sets the per-user `hidden` flag). WhatsApp parity: the
  /// chat stays archived even when a new message arrives; only an explicit
  /// [unarchive] (or [unhide]) brings it back to the main list. Distinct
  /// from [delete], which removes the chat from BOTH sections.
  Future<ChatResult<void>> hide(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(hidden: v),
    true,
    (id) => _a.client.rooms.patchPreferences(id, hidden: true).discardValue(),
    OperationKind.hideRoom,
  );

  /// Reveals a previously hidden [roomId] (clears the `hidden` flag).
  Future<ChatResult<void>> unhide(String roomId) => _a._toggleRoomFlag(
    roomId,
    (r, v) => r.copyWith(hidden: v),
    false,
    (id) => _a.client.rooms.patchPreferences(id, hidden: false).discardValue(),
    OperationKind.unhideRoom,
  );

  /// UNARCHIVE — restores an archived [roomId] to the main list. Inverse
  /// of [hide]; alias of [unhide] kept distinct so the in-chat three-dots
  /// menu reads as "Unarchive" rather than the lower-level "Unhide".
  Future<ChatResult<void>> unarchive(String roomId) => unhide(roomId);

  /// DELETE — WhatsApp "Delete chat". Removes [roomId] from BOTH the main
  /// list and the Archived section, permanently from the user's point of
  /// view. It reappears EMPTY only if a 1:1 peer writes again (the
  /// resurrection path in the event router clears the deleted marker but
  /// leaves the `clearedAt` cutoff in place so prior history stays hidden).
  ///
  /// Unlike [hide] (archive) this is NOT just a `hidden` flag: it writes a
  /// dedicated, never-evictable per-user `deletedRooms` marker AND sets the
  /// `clearedAt` cutoff to now (reusing the same mechanism as
  /// `messages.clearChat`), then drops the row from the controller. No
  /// server membership change happens (use [leave] to leave a group).
  ///
  /// Both markers are written through the CLIENT surface
  /// (`client.messages.setLocalClearedAt` / `client.rooms.markRoomDeleted`)
  /// — same pattern `messages.clearChat` already uses — so they persist
  /// even when this [ChatUiAdapter] was built without its own `cache:` arg
  /// (e.g. WB, which only wires `ChatConfig.localDatasource` at the client
  /// level). The adapter-level cache, when present, is written to as well
  /// as a backstop for hosts that relied on it directly.
  Future<ChatResult<void>> delete(String roomId) async {
    final cache = _a._cache;
    final now = DateTime.now().toUtc();
    await _a.client.messages
        .setLocalClearedAt(roomId, now)
        .catchError(_swallowCacheThrow);
    await _a.client.rooms.markRoomDeleted(roomId).catchError(
      _swallowCacheThrow,
    );
    // Persist the cutoff so any prior history stays hidden if the room is
    // re-fetched later (twin of the never-evictable deleted marker).
    if (cache != null) {
      await cache.setClearedAt(roomId, now).catchError(_swallowCacheThrow);
      await cache.clearMessages(roomId).catchError(_swallowCacheThrow);
      await cache.clearPendingMessages(roomId).catchError(_swallowCacheThrow);
      await cache.addDeletedRoom(roomId).catchError(_swallowCacheThrow);
    }
    // Also clear the open controller's in-memory history so re-opening the
    // chat right after deleting shows it empty (mirrors clearChat).
    _a._chatControllers[roomId]?.clearMessages();
    _a.roomListController.markDeleted(roomId);
    return const ChatSuccess<void>(null);
  }

  /// Removes the current user from [roomId]. The row is kept (flipped to
  /// read-only via `isParticipating=false`) and a durable `markKicked`
  /// marker is persisted, so a voluntary leave lands in the same
  /// kicked-read-only mechanism as a server-side kick and survives sync.
  /// The open chat controller is preserved so the chat stays browsable.
  Future<ChatResult<void>> leave(String roomId) async {
    final result = await _a.client.members.leave(roomId);
    if (result.isSuccess) {
      final room = _a.roomListController.getRoomById(roomId);
      if (room != null && room.isParticipating) {
        _a.roomListController.updateRoom(room.copyWith(isParticipating: false));
      }
      final cache = _a._cache;
      if (cache != null) {
        await cache.markKicked(roomId).catchError(_swallowCacheThrow);
      }
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
    final inviteResult = await _a.client.members.invite(
      roomId,
      userIds: [_a.currentUser.id],
      mode: RoomUserMode.acceptInvitation,
    );
    final result = inviteResult.isSuccess
        ? const ChatSuccess<void>(null)
        : ChatFailureResult<void>(inviteResult.failureOrNull!);
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

  /// Invites [userIds] to [roomId]. A partial failure (some users added,
  /// others rejected — banned, already a member) surfaces as a failure with
  /// the per-user reasons, instead of being silently swallowed.
  Future<ChatResult<void>> addMembers(
    String roomId,
    List<String> userIds, {
    RoomUserMode mode = RoomUserMode.inviteAndJoin,
  }) async {
    final inviteResult = await _a.client.members.invite(
      roomId,
      userIds: userIds,
      mode: mode,
    );
    final result = switch (inviteResult) {
      ChatSuccess(:final data) when data.hasFailures => ChatFailureResult<void>(
        ValidationFailure(
          message: 'Some users could not be added',
          errors: {for (final f in data.failed) f.userId: f.detail ?? 'failed'},
        ),
      ),
      ChatSuccess() => const ChatSuccess<void>(null),
      ChatFailureResult(:final failure) => ChatFailureResult<void>(failure),
    };
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

  /// Opens [roomId], fetching its detail from the server when it isn't
  /// already known to [ChatUiAdapter.roomListController] — the deep-link
  /// case, e.g. a push notification or a shared link pointing at a room
  /// the local list/cache hasn't synced yet.
  ///
  /// Returns a ready [ChatController] on success. On failure the
  /// [ChatFailure] is typed so the host can branch instead of collapsing
  /// every case to "this chat doesn't exist": [NotFoundFailure] (the room
  /// truly doesn't exist, or the user isn't a member), [AuthFailure] /
  /// [ForbiddenFailure] (session/permission problem — NOT the same as "not
  /// found"), or [NetworkFailure] / [TimeoutFailure] (transient — retry,
  /// don't tell the user the chat is gone).
  ///
  /// Pass `fetchIfMissing: false` to restrict the lookup to what's already
  /// in the room list (returns [NotFoundFailure] instead of hitting the
  /// network) — e.g. for a caller that wants to distinguish "known room" UI
  /// from "unknown, would need a fetch" without paying for the round-trip.
  Future<ChatResult<ChatController>> open(
    String roomId, {
    bool fetchIfMissing = true,
  }) async {
    if (_a.roomListController.getRoomById(roomId) != null) {
      return ChatSuccess(_a.getChatController(roomId));
    }
    if (!fetchIfMissing) {
      return const ChatFailureResult<ChatController>(NotFoundFailure());
    }
    // Fast-fail instead of waiting out the full `requestTimeout` (default
    // 30s): the client already knows the realtime channel is down, so a
    // fresh REST round-trip is very unlikely to fare any better. Only
    // `disconnected` counts as "known offline" — `connecting` /
    // `reconnecting` / `authenticating` are still actively trying and a
    // REST call can succeed independently of the WS state.
    if (_a.connectionState == ChatConnectionState.disconnected) {
      return const ChatFailureResult<ChatController>(
        NetworkFailure('Offline: room not fetched'),
      );
    }
    final result = await _a.client.rooms.get(
      roomId,
      cachePolicy: CachePolicy.networkOnly,
    );
    if (result.isFailure) return result.castFailure<ChatController>();
    _a._enricher.applyFetchedDetail(roomId, result.dataOrThrow);
    return ChatSuccess(_a.getChatController(roomId));
  }
}
