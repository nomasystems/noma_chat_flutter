part of '../chat_ui_adapter.dart';

/// Everything [ChatUiAdapter] does to a room rather than to a message: the
/// per-room [ChatController] registry and the active-room pointer, the
/// direct-message routing helpers, the room list load, the optimistic
/// flags (mute, pin, hide), membership and configuration writes,
/// invitations and the kicked-chat cleanup.
///
/// Lives next to the adapter as a `part` and is mixed into [ChatUiAdapter],
/// so every member stays a real instance member of the adapter and reads
/// and writes the same private fields it did when it sat in the class body.
mixin _AdapterRoomActions on _AdapterCore {
  /// Returns (or creates) a [ChatController] for the given room.
  ///
  /// When [otherUsers] is supplied it is cached and pushed onto the
  /// controller as before. When it is omitted, the adapter fills the
  /// controller's peer list from what it already knows — the resolved DM
  /// contact (see [DmContactRegistry]) hydrated from the in-memory user
  /// cache. Consumers therefore no longer need the `cacheUsers(...)` +
  /// `setOtherUsers(...)` double-call just to get the DM peer onto a
  /// freshly-opened controller; opening the room is enough.
  ChatController getChatController(
    String roomId, {
    List<ChatMessage> initialMessages = const [],
    List<ChatUser> otherUsers = const [],
  }) {
    if (otherUsers.isNotEmpty) cacheUsers(otherUsers);
    final effectiveOthers = otherUsers.isNotEmpty
        ? otherUsers
        : _cachedOtherUsersForRoom(roomId);
    final existing = _chatControllers[roomId];
    if (existing != null) {
      // Only push when the caller actually supplied users, or when the
      // controller has none yet and we resolved some from cache — never
      // clobber a populated controller with an empty/cache-only list.
      if (otherUsers.isNotEmpty) {
        existing.setOtherUsers(otherUsers);
      } else if (existing.otherUsers.isEmpty && effectiveOthers.isNotEmpty) {
        existing.setOtherUsers(effectiveOthers);
      }
      return existing;
    }
    final controller = ChatController(
      initialMessages: initialMessages,
      currentUser: currentUser,
      otherUsers: effectiveOthers,
    );
    controller.setRoomId(roomId);
    _chatControllers[roomId] = controller;
    return controller;
  }

  /// Disposes and removes the controller for a room. When [autoMarkAsRead]
  /// is true (default), flushes a `markAsRead` for the room before disposing
  /// so the chat list unread counter and last-read pointer stay in sync
  /// with what the user actually saw (mirrors WhatsApp's "close chat" flush).
  void removeChatController(String roomId) {
    if (autoMarkAsRead && _chatControllers.containsKey(roomId)) {
      unawaited(markAsRead(roomId));
    }
    if (_activeRoomId == roomId) _activeRoomId = null;
    _chatControllers.remove(roomId)?.dispose();
  }

  /// Marks [roomId] as the currently-foregrounded chat. Pass `null` when
  /// the user leaves it. Zeroes the room-list unread badge immediately —
  /// optimistically, on the client, synchronously with this call — instead
  /// of waiting for `markAsRead`'s network round-trip, so the badge clears
  /// the instant the user opens the room even on a slow/unstable
  /// connection, matching WhatsApp. Also triggers the real `markAsRead`
  /// request for [roomId] if [autoMarkAsRead] is true (cheap; idempotent
  /// when nothing changed) so the server's read cursor still advances.
  void setActiveRoom(String? roomId) {
    if (_activeRoomId == roomId) return;
    _activeRoomId = roomId;
    // A draft DM has no backend room yet (it materializes on the first sent
    // message), so mark-as-read would 403 with `not_member`. Skip it for
    // drafts; the room is marked read normally once it materializes.
    final isDraftRoom =
        roomId != null &&
        ((_chatControllers[roomId]?.isDraft ?? false) ||
            dm.isDraftRoutingKey(roomId));
    if (roomId != null && !isDraftRoom) {
      emitAnalyticsEvent(
        ChatAnalyticsEvent.roomOpened(
          roomId: roomId,
          isGroup: roomListController.getRoomById(roomId)?.isGroup ?? false,
        ),
      );
      // The roster frames that keep `memberCount` (and the title, the
      // avatar, the read-only flag) current are the only thing that
      // refreshes them, so a single frame lost to a dropped socket left
      // the header contradicting the room for as long as the row lived —
      // leaving and re-entering it changed nothing, because nothing
      // re-read the detail on the way in. Opening the room is the cheap,
      // self-healing moment to re-read it: once per entry, single-flighted
      // by the enricher.
      if (roomListController.getRoomById(roomId) != null) {
        _enrichRoomFromDetail(roomId);
      }
    }
    if (roomId != null && autoMarkAsRead && !isDraftRoom) {
      final targetRoomId = roomId;
      scheduleMicrotask(() {
        if (!_disposed && _activeRoomId == targetRoomId) {
          _roomListMutator.updateRoomUnread(targetRoomId, 0);
        }
      });
      unawaited(markAsRead(roomId));
    }
  }

  /// Returns the [ChatController] for [roomId] only if it has already been
  /// created (does NOT create a new one). Useful for read-only lookups such as
  /// resolving member names from the room list.
  ChatController? findChatController(String roomId) => _chatControllers[roomId];

  /// Associates a contact user ID with its DM room ID for typing indicator routing.
  @internal
  void registerDmRoom(String contactUserId, String roomId) =>
      dm.registerRoom(contactUserId, roomId);

  /// Returns the room ID for a DM with the given contact, or null.
  @internal
  String? getDmRoomId(String contactUserId) => dm.getRoomId(contactUserId);

  /// Returns the existing DM room id with [otherUserId] if there is one, or
  /// `null` if no conversation has been started yet. Checks the contact→room
  /// cache first (`getDmRoomId`) and falls back to scanning the room list for
  /// rows with `otherUserId == otherUserId`.
  ///
  /// Use this before calling [openDirectMessageDraft] to decide whether to
  /// open the existing conversation (`getChatController(existingId)`) or
  /// start a fresh draft.
  @internal
  String? findExistingDmRoom(String otherUserId) =>
      dm.findExisting(otherUserId);

  /// Opens a draft DM with [otherUserId] WhatsApp-style — returns a
  /// [ChatController] in `isDraft` state without creating a room
  /// server-side. The other user is hydrated (from cache or
  /// `client.users.get`) so `controller.otherUsers` is populated and
  /// downstream consumers (e.g. AppBars resolving titles via
  /// `RoomTitleResolver`) can render immediately.
  ///
  /// The draft is cached under the key `draft:<otherUserId>` in
  /// `_chatControllers`. The first successful send through this controller
  /// materializes a real room (`rooms.create` with `members: [otherUserId]`,
  /// plus any [extraRoomCustom]) — see `_OptimisticHandler.sendMessage`.
  ///
  /// Callers that want to reuse an existing conversation should call
  /// [findExistingDmRoom] first.
  ///
  /// [extraRoomCustom] is merged into the `custom` map of the
  /// materialized room. Pass `{'type': 'dm'}` (or whatever marker your app
  /// uses) when the [IsDmRoomPredicate] needs an explicit hint to recognize
  /// the room as a DM.
  @internal
  Future<ChatController> openDirectMessageDraft(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.openDraft(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Key under which a draft DM controller is cached in `_chatControllers`.
  /// Exposed publicly so the UI layer can pass it to [sendMessage] (and
  /// other room-id-keyed APIs) before the draft has been materialized into
  /// a real room. Format: `draft:<otherUserId>`.
  @internal
  String draftRoutingKey(String otherUserId) => dm.draftRoutingKey(otherUserId);

  // Note: draft DM custom payloads (the per-contact map previously
  // here as `_draftRoomCustomByOtherUser`) live in [_dmContacts]
  // under `draftCustomFor`/`setDraftCustom` — same lifecycle as the
  // DM mapping itself, so a single service owns both.

  /// Returns the real server-side `roomId` for the DM with [otherUserId],
  /// creating the room if it does not exist yet. Idempotent — three branches:
  ///
  /// 1. There is already a known room with this contact
  ///    ([findExistingDmRoom] returns non-null) → returns that id.
  /// 2. There is an open draft controller for this contact
  ///    (`_chatControllers['draft:<otherUserId>']`): create the room via
  ///    `client.rooms.create`, rebind the controller from the draft slot to
  ///    the real id (`setRoomId` + `clearDraft`), seed `_dmRoomByContact`,
  ///    and add the row to the room list. Returns the real id.
  /// 3. No room and no draft: same as (2) but no controller to rebind. The
  ///    consumer typically calls [getChatController] afterwards.
  ///
  /// Use this from flows that need the real `roomId` BEFORE sending — e.g.
  /// uploading an attachment whose progress is tied to a row in the list,
  /// or any operation routed via `roomId` (typing, voice send, etc.). The
  /// optimistic `sendMessage` materializes on its own; consumers that only
  /// send text don't need to call this directly.
  ///
  /// [extraRoomCustom] overrides any custom payload previously registered
  /// for [otherUserId] via [openDirectMessageDraft]. Useful for ad-hoc
  /// callers without a draft controller.
  ///
  /// Failures propagate the underlying `ChatResult.ChatFailureResult` so the consumer can
  /// surface a retry. A failure does NOT leave a stale draft entry — the
  /// controller stays in `isDraft = true` and can retry on the next send.
  @internal
  Future<ChatResult<String>> ensureDmRoomMaterialized(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.ensureMaterialized(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Fetches rooms from the server and populates the [roomListController].
  /// Loads user rooms using cache-then-network:
  /// 1. Shows cached room list instantly (if available).
  /// 2. Fetches fresh room list from network and replaces — unless
  ///    realtime (WS) is already connected and the adapter has been
  ///    initialized at least once. In that case the cache is trusted
  ///    and the network round-trip is skipped: incoming events keep
  ///    the room list up-to-date in real time.
  ///
  /// Pass [forceNetwork] to bypass the realtime optimization — useful
  /// for pull-to-refresh interactions where the user explicitly asks
  /// for a fresh server snapshot.
  ///
  /// A successful response — from this call, [resync]'s automatic pass
  /// after a reconnect, or the background revalidation fired by the
  /// cache-trusted branch above — is always treated as the caller's
  /// authoritative complete room set, including when it's legitimately
  /// empty: the listing endpoint fails outright on a bad read instead of
  /// answering 200 with a partial/best-effort page, so there's no
  /// ambiguity left for the client to guard against. A failed response
  /// (network error, timeout, 5xx) never touches the list, here or in any
  /// caller.
  @internal
  @override
  Future<ChatResult<void>> loadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => rooms.load(type: type, forceNetwork: forceNetwork);

  Future<ChatResult<void>> _doLoadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => _enricher.loadAll(type: type, forceNetwork: forceNetwork);

  /// Generic optimistic toggle for a boolean room flag (muted / pinned /
  /// hidden). Flips the visible state immediately, calls [apiCall], and
  /// rolls back on failure. Emits an [OperationError] through
  /// [operationErrors] tagged with [kind] when the API call fails.
  ///
  /// Captured as a helper because the 6 toggle methods below — mute,
  /// unmute, pin, unpin, hide, unhide — share the exact same flow, just
  /// differing on which `RoomListItem` field flips and which `client.rooms`
  /// endpoint runs.
  Future<ChatResult<void>> _toggleRoomFlag(
    String roomId,
    RoomListItem Function(RoomListItem room, bool value) applyFlag,
    bool desiredValue,
    Future<ChatResult<void>> Function(String roomId) apiCall,
    OperationKind kind,
  ) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(applyFlag(room, desiredValue));
    }
    final result = await apiCall(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(applyFlag(room, !desiredValue));
    }
    return _emitFailure(result, kind, roomId: roomId);
  }

  /// Mutes a room with optimistic update. Pass [until] for a timed mute.
  @internal
  Future<ChatResult<void>> muteRoom(String roomId, {DateTime? until}) =>
      rooms.mute(roomId, until: until);

  /// Unmutes a room with optimistic update.
  @internal
  Future<ChatResult<void>> unmuteRoom(String roomId) => rooms.unmute(roomId);

  /// Pins a room with optimistic update.
  @internal
  Future<ChatResult<void>> pinRoom(String roomId) => rooms.pin(roomId);

  /// Unpins a room with optimistic update.
  @internal
  Future<ChatResult<void>> unpinRoom(String roomId) => rooms.unpin(roomId);

  /// Hides a room with optimistic update (removes from visible list).
  @internal
  Future<ChatResult<void>> hideRoom(String roomId) => rooms.hide(roomId);

  /// Unhides a room with optimistic update.
  @internal
  Future<ChatResult<void>> unhideRoom(String roomId) => rooms.unhide(roomId);

  /// Blocks a contact. WhatsApp-parity: the DM room STAYS in the
  /// blocker's chat list with full history — the composer is replaced
  /// by a "tap to unblock" banner (see [ChatView.isBlocked]) so the
  /// blocker can reverse course. The previous implementation removed
  /// the room entirely and forced consumers to pop the chat page,
  /// which lost the conversation context and surprised users.
  ///
  /// Adds [userId] to [blockedUserIds] and fires
  /// [onBlockedUsersChanged] so the host UI can react (e.g. hide
  /// suggestions, swap the composer for the blocked banner).
  @internal
  Future<ChatResult<void>> blockContact(String userId, {String? roomId}) =>
      contacts.block(userId, roomId: roomId);

  /// Unblocks a contact in the chat system. Removes [userId] from
  /// [blockedUserIds] and fires [onBlockedUsersChanged]. Does NOT
  /// recreate the DM row — consumers that need the room back should
  /// call [loadRooms] or open a fresh draft via
  /// [openDirectMessageDraft].
  @internal
  Future<ChatResult<void>> unblockContact(String userId) =>
      contacts.unblock(userId);

  /// Adds [userIds] to [roomId] as group members. WhatsApp-style default:
  /// [mode] = `RoomUserMode.inviteAndJoin` — the invited users join
  /// immediately without requiring an accept step. Apps that need an
  /// invitation-then-accept flow pass [mode] = `RoomUserMode.invite`.
  ///
  /// On success the adapter does NOT mutate the local
  /// [roomListController] directly — the backend emits a
  /// `UserJoinedEvent` per added user that the event router already
  /// turns into `ChatController.setOtherUsers` updates and metadata
  /// refreshes. This keeps the local state consistent with anyone else
  /// observing the same room (multi-device, web client, etc.).
  @internal
  Future<ChatResult<void>> addMembers(
    String roomId,
    List<String> userIds, {
    RoomUserMode mode = RoomUserMode.inviteAndJoin,
  }) => rooms.addMembers(roomId, userIds, mode: mode);

  /// Updates room metadata (name, subject, avatar, custom). Wrapper
  /// around `client.rooms.updateConfig` that emits [operationErrors]
  /// with [OperationKind.updateRoomConfig] on failure. Backend gates
  /// this on owner/admin role; non-privileged callers get a 403.
  @internal
  Future<ChatResult<void>> updateRoomConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => rooms.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    custom: custom,
  );

  /// Creates a group room in a single hop, optionally uploading an
  /// avatar first. Returns the newly-created room id on success so the
  /// caller can navigate straight into it.
  @internal
  Future<ChatResult<String>> createGroupRoom({
    required String name,
    required List<String> memberIds,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    String? subject,
    bool allowInvitations = false,
    RoomAudience audience = RoomAudience.contacts,
    Map<String, dynamic>? custom,
  }) => rooms.createGroup(
    name: name,
    memberIds: memberIds,
    avatarBytes: avatarBytes,
    avatarMimeType: avatarMimeType,
    subject: subject,
    allowInvitations: allowInvitations,
    audience: audience,
    custom: custom,
  );

  /// Removes [userId] from [roomId] — used by admins to kick a member.
  /// The backend rejects the call (403) if the caller lacks the
  /// permission; the SDK surfaces the failure via [operationErrors] like
  /// any other adapter op. On success the backend emits `UserLeftEvent`
  /// to all participants, which `ChatEventRouter` already handles.
  @internal
  Future<ChatResult<void>> removeMember(String roomId, String userId) =>
      rooms.removeMember(roomId, userId);

  /// Updates [userId]'s [RoomRole] inside [roomId] — admins promote
  /// members or demote other admins. Backend rejects if the caller lacks
  /// the permission (the SDK surfaces the failure via [operationErrors]).
  /// On success the backend emits `UserRoleChangedEvent` and the event
  /// router refreshes member lists.
  @internal
  Future<ChatResult<void>> updateMemberRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => rooms.updateMemberRole(roomId, userId, role);

  /// Leaves a room and removes it from the list.
  @internal
  Future<ChatResult<void>> leaveRoom(String roomId) => rooms.leave(roomId);

  /// Accepts a room invitation.
  @internal
  Future<ChatResult<void>> acceptInvitation(String roomId) =>
      rooms.acceptInvitation(roomId);

  /// Rejects a room invitation and removes it from the list. Restores the
  /// row on failure so a network glitch does not silently lose the invite.
  @internal
  Future<ChatResult<void>> rejectInvitation(String roomId) =>
      rooms.rejectInvitation(roomId);

  /// Adds a room to the controller AFTER a successful detail fetch.
  ///
  /// Used when the adapter learns about a new room via realtime events
  /// (`NewMessageEvent`, `RoomCreatedEvent`) and the room is not yet in the
  /// controller. We deliberately do NOT add a placeholder `RoomListItem(id:)`
  /// because doing so would cause the UI to briefly render a "ghost" room
  /// (raw roomId as title, no avatar) until the detail enrichment succeeds.
  ///
  /// If the detail fetch fails, the room is not added. The next `loadRooms`
  /// call will pick it up if the server still knows about it.
  void _addRoomFromDetail(String roomId, {ChatMessage? lastMessage}) =>
      _enricher.addFromDetail(roomId, lastMessage: lastMessage);

  @override
  void _enrichRoomFromDetail(String roomId) => _enricher.refreshRoom(roomId);

  /// "Delete kicked chat" — WhatsApp's option to manually remove a
  /// chat the user was kicked from. Drops it from the room list,
  /// clears the local cache for the room (messages, detail,
  /// unreads), and unmarks the kicked flag. No network call — the
  /// server already considers the user removed.
  ///
  /// Surfaced via [ChatRoomOption.deleteKickedChat] in the room
  /// options menu when `room.isParticipating == false`. Safe to
  /// call on participating rooms too (does the same cleanup), but
  /// the UI only exposes it after a kick.
  @internal
  Future<void> deleteKickedChat(String roomId) => rooms.deleteKicked(roomId);
}
