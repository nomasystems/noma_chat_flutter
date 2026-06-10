import 'dart:typed_data';

import '../cache/cache_policy.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/attachment.dart';
import '../models/contact.dart';
import '../models/health_status.dart';
import '../models/managed_user_config.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/presence.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/report.dart';
import '../models/room.dart';
import '../models/room_user.dart';
import '../models/scheduled_message.dart';
import '../models/unread_room.dart';
import '../models/user.dart';
import '../models/user_rooms.dart';

/// Entry point for all chat operations.
///
/// Provides sub-API accessors for users, rooms, messages, contacts,
/// presence, and attachments. Call [connect] to start receiving real-time
/// events, and [dispose] when the client is no longer needed.
///
/// Most callers do not implement this interface directly — use
/// `NomaChat.client` from the top-level facade, which wires the concrete
/// implementation (transport, cache, offline queue) from [ChatConfig].
abstract class ChatClient {
  /// Authentication and server health checks.
  ChatAuthApi get auth;

  /// User search, creation, update, and managed-user operations.
  ChatUsersApi get users;

  /// Room lifecycle: create, list, discover, configure, mute, pin.
  ChatRoomsApi get rooms;

  /// Room membership: invite, remove, ban, role management.
  ChatMembersApi get members;

  /// Send, edit, delete messages; receipts, typing, threads, pins, search.
  ChatMessagesApi get messages;

  /// Contact list, direct messages, blocking.
  ChatContactsApi get contacts;

  /// Online presence status for the current user and contacts.
  ChatPresenceApi get presence;

  /// File upload, download, and per-room attachment listing.
  ChatAttachmentsApi get attachments;

  /// Stream of real-time events (messages, typing, presence, etc.).
  ///
  /// Subscribe once at startup and route events through your own
  /// state-management layer. The stream is broadcast: multiple
  /// listeners are allowed, but each one will receive every event so
  /// dedupe on the consumer side if needed.
  Stream<ChatEvent> get events;

  /// Current connection state.
  ///
  /// Snapshot value — for live updates subscribe to [stateChanges]
  /// instead. Useful for one-shot checks (e.g. "should I disable the
  /// composer right now?").
  ChatConnectionState get connectionState;

  /// Stream that emits whenever the connection state changes.
  ///
  /// Use this to drive a connectivity banner or to disable optimistic
  /// sends when the channel is `disconnected`. Emits the new state only
  /// (not the previous one); pair with [connectionState] if you need
  /// both.
  Stream<ChatConnectionState> get stateChanges;

  /// Opens the real-time connection (WebSocket/SSE/polling) honoring
  /// [ChatConfig.realtimeMode].
  ///
  /// Call once after successful authentication. Re-entrant: calling
  /// [connect] while already connected is a cheap no-op; calling it
  /// after a [disconnect] re-opens the channel.
  Future<void> connect();

  /// Closes the real-time connection without clearing state.
  ///
  /// Cached rooms/messages and the event stream stay alive — use this
  /// when the app goes to background and you want to release the socket
  /// but keep the UI hydrated. Pair with [connect] when the app
  /// returns to foreground. Idempotent: safe to call when already
  /// disconnected.
  Future<void> disconnect();

  /// Notifies the server (via WebSocket) that the auth token has been rotated.
  ///
  /// Call this immediately after refreshing the JWT while a real-time
  /// connection is open, so the server can update its session record
  /// without forcing a reconnect. If the channel is closed (or running
  /// in `manual`/`polling` mode without a live socket) this is a no-op.
  Future<void> notifyTokenRotated();

  /// Force a refresh of the room list and (in `polling`/`manual` modes)
  /// pull new messages for any room that changed.
  ///
  /// Wire to a global pull-to-refresh on the room list screen. Streaming
  /// modes (`auto`, `webSocketOnly`, `serverSentEventsOnly`) are no-op
  /// — the event stream already delivers updates as they happen, so
  /// calling `refresh()` there is safe but redundant.
  Future<void> refresh();

  /// Like [refresh] but scoped to a single room.
  ///
  /// Wire to a per-chat pull-to-refresh in [RealtimeMode.manual]; in
  /// `polling` it skips the next room-list diff and pulls messages for
  /// [roomId] only. Streaming modes: no-op (same caveat as [refresh]).
  Future<void> refreshRoom(String roomId);

  /// Disconnects and clears all local state (rooms, messages, contacts).
  ///
  /// Call on user-initiated sign-out. Unlike [disconnect], this also
  /// wipes the local cache so the next sign-in starts cold. Do NOT use
  /// for background/foreground transitions — that's [disconnect]. The
  /// client remains usable after [logout]; you can re-authenticate and
  /// call [connect] again on the same instance.
  Future<void> logout();

  /// Releases all resources. The client must not be used after this call.
  ///
  /// Closes streams, cancels timers, and disposes the underlying HTTP /
  /// WS clients. Idempotent: a second call is a no-op. Any method
  /// invoked after [dispose] returns a failure or throws — treat the
  /// instance as dead.
  Future<void> dispose();

  /// Cancels every in-flight REST request.
  ///
  /// Fire this before tearing down the session (logout, dispose) so
  /// pending HTTP calls do not race against a token provider that has
  /// just been invalidated — without it a 401 on a stale request could
  /// trigger an auth refresh + `onAuthFailure` against already-closed
  /// UI. The default implementation in [NomaChatClient] also wires this
  /// into [logout] and [dispose] automatically; consumers usually do
  /// not need to call it directly.
  void cancelPendingRequests([String reason]);

  /// Optional callback invoked by clients with an offline queue when a
  /// queued send completes after the connection is restored.
  ///
  /// The callback receives the room id, the original optimistic temp
  /// id, and the server-confirmed message — use it to reconcile the
  /// optimistic bubble in your UI with the authoritative message.
  /// Clients that do not implement an offline queue may leave this as a
  /// no-op setter.
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  );
}

/// Server health and authentication checks.
abstract class ChatAuthApi {
  /// Returns the server health status including individual service checks.
  ///
  /// Use this to gate splash screens or a diagnostics page — it pings
  /// the backend without authenticating, so it works before login. The
  /// returned [HealthStatus] reports per-component liveness (DB, cache,
  /// realtime) so you can render granular status, not just up/down.
  Future<ChatResult<HealthStatus>> healthCheck();
}

/// User search, creation, profile updates, and managed-user operations.
abstract class ChatUsersApi {
  /// Searches users by display name (case-insensitive substring match).
  ///
  /// Use this to power the new-chat picker or @-mention autocomplete.
  /// Always paginated — the backend caps very broad queries; pass a
  /// [pagination] with a sensible `limit` (the UI adapter typically
  /// uses 20) and load more on scroll. Empty/whitespace queries return
  /// no results.
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> search(
    String query, {
    ChatPaginationParams? pagination,
  });

  /// Fetches a single user by ID.
  ///
  /// Use to hydrate the "other user" row in a 1:1 chat or to enrich
  /// member lists with display name + avatar. [cachePolicy] defaults to
  /// `networkFirst`; pass `cacheFirst` for hot paths (message bubbles)
  /// and `networkOnly` when you need an authoritative snapshot (e.g.
  /// settings page showing your own current profile).
  ///
  /// ```dart
  /// final res = await client.users.get(otherUserId);
  /// res.dataOrNull?.let((u) => controller.addOtherUser(u));
  /// ```
  Future<ChatResult<ChatUser>> get(String userId, {CachePolicy? cachePolicy});

  /// Creates a new user, optionally linked to external IDs and seeded
  /// with profile fields (1-step creation).
  ///
  /// Use during onboarding to register the authenticated principal
  /// against the chat backend. The auth-derived id is always used; the
  /// optional profile fields become the initial values for the new
  /// record (backend ignores them if it doesn't support inline profile
  /// creation — falls back to bare create). Subsequent calls for the
  /// same auth principal return the existing user instead of erroring,
  /// so this is safe to call on every cold start.
  Future<ChatResult<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
  });

  /// Updates profile fields for an existing user.
  ///
  /// Call this from the profile editor when the user saves their
  /// changes. The backend emits a `user_updated` WS event so the
  /// authenticated principal's other devices (and rooms that render
  /// their avatar/name) see the change in real time.
  ///
  /// Pass `clearAvatar: true` to explicitly remove the current avatar
  /// (sends an explicit JSON null so the backend wipes the field).
  /// Passing `avatarUrl: null` without the flag is a no-op — the field
  /// is omitted from the payload entirely.
  Future<ChatResult<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    bool clearAvatar,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  });

  /// Deletes a user permanently.
  ///
  /// Use for hard account deletion flows (GDPR right-to-erasure or
  /// admin tools). Irreversible — the backend tombstones messages but
  /// removes the profile record; managed users belonging to the
  /// deleted parent are cascaded out too.
  Future<ChatResult<void>> delete(String userId);

  /// Finds a managed user by its external ID.
  ///
  /// Use when integrating with an external identity system (e.g.
  /// "given this CRM contact id, do we already have a managed user?")
  /// before deciding whether to [createManaged]. Returns a failure if
  /// no match — does not auto-create.
  Future<ChatResult<ChatUser>> searchManaged({required String externalId});

  /// Creates managed users linked to the given external IDs.
  ///
  /// Managed users are owned by the authenticated principal (the
  /// "parent") and are typically bots, service accounts, or proxy
  /// identities for users that live in another system. Pass multiple
  /// external IDs to batch-create in a single round-trip.
  Future<ChatResult<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  });

  /// Lists managed users belonging to a parent user.
  ///
  /// Use to power an admin/owner list of "users I manage". Always
  /// paginated; backend defaults apply when [pagination] is omitted.
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManaged(
    String userId, {
    ChatPaginationParams? pagination,
  });

  /// Removes a managed user from its parent.
  ///
  /// Detaches the link but does NOT delete the underlying user
  /// account; the same external ID can later be re-attached via
  /// [createManaged]. [fromUserId] is the parent — required because a
  /// managed user can in principle have multiple parents.
  Future<ChatResult<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  });

  /// Gets the configuration of a managed user (webhooks, metadata).
  ///
  /// Use from an admin/integration panel to inspect the webhook URL
  /// that the backend will POST to when the managed user receives
  /// messages, plus arbitrary metadata used by the parent app.
  Future<ChatResult<ManagedUserConfiguration>> getManagedConfig(String userId);

  /// Updates the configuration of a managed user.
  ///
  /// Pass a full [ManagedUserConfiguration] — the backend replaces the
  /// stored config wholesale (no partial PATCH). Use [getManagedConfig]
  /// + `copyWith` if you only want to tweak one field.
  Future<ChatResult<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  });
}

/// Room lifecycle: creation, listing, discovery, configuration, and user preferences.
abstract class ChatRoomsApi {
  /// Creates a new room with the given audience and optional initial members.
  ///
  /// For a 1:1 DM pass `audience: RoomAudience.unrestricted` and a
  /// single peer in [members] — the backend reuses an existing 1:1 room
  /// if one already exists between the two users, so this is safe to
  /// call on every "open DM" tap. For groups pass [name] and the
  /// initial roster. The created room emits `room_created` over WS so
  /// other devices/members see it appear in real time.
  ///
  /// ```dart
  /// final res = await client.rooms.create(
  ///   audience: RoomAudience.unrestricted,
  ///   members: [otherUserId],
  /// );
  /// ```
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  });

  /// Lists the current user's rooms. Use type 'unread' to filter rooms with unread messages.
  ///
  /// Primary feed for the home screen. [cachePolicy] defaults to
  /// `networkFirst`; the UI adapter passes `cacheFirst` for the first
  /// paint and re-issues with `networkOnly` on pull-to-refresh.
  /// `type='unread'` is a cheap server-side filter — preferred over
  /// listing all and filtering client-side.
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  });

  /// Searches public rooms by name or subject.
  ///
  /// Use to power a "discover groups" screen. Only returns rooms with
  /// `audience: public`; private/contacts/unrestricted rooms are
  /// invisible regardless of membership. Paginated — backend caps at a
  /// reasonable default when [pagination] is omitted.
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  });

  /// Fetches full room details including config, member count, and user role.
  ///
  /// Heavier than the entry returned by [getUserRooms] — call when the
  /// user opens the room info panel, not for every list refresh.
  /// [cachePolicy] follows the standard semantics; `cacheFirst` is the
  /// common choice for the info panel so it opens instantly and then
  /// reconciles when the network response arrives.
  Future<ChatResult<RoomDetail>> get(String roomId, {CachePolicy? cachePolicy});

  /// Deletes a room permanently. Requires owner/admin role.
  ///
  /// Irreversible. Backend emits `room_deleted` to all members so other
  /// devices remove the room from their list immediately. Non-privileged
  /// callers get a 403 — the SDK surfaces this as a [ChatResult] failure
  /// rather than throwing.
  Future<ChatResult<void>> delete(String roomId);

  /// Updates room metadata (name, subject, avatar, custom data).
  ///
  /// Use from the room settings screen — pass only the fields you want
  /// to change (others are omitted from the payload entirely). Backend
  /// gates on owner/admin role; non-privileged callers get a 403. On
  /// success the backend emits `room_updated` so other members see the
  /// change in real time.
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar,
    Map<String, dynamic>? custom,
  });

  /// Mutes push notifications for a room.
  ///
  /// Per-user preference: only affects the calling user's push channel
  /// — other members still receive notifications. Idempotent. Backend
  /// emits no event for this; the local cache reflects the change for
  /// this device, and other devices see the new state on their next
  /// room-list fetch.
  Future<ChatResult<void>> mute(String roomId);

  /// Unmutes push notifications for a room.
  ///
  /// Per-user preference, same multi-device caveat as [mute]. Idempotent.
  Future<ChatResult<void>> unmute(String roomId);

  /// Pins a room to the top of the room list.
  ///
  /// Per-user preference — pins are private and not visible to other
  /// members. Idempotent: pinning an already-pinned room is a no-op.
  /// The UI adapter keeps pinned rooms ordered above the rest in the
  /// room list controller.
  Future<ChatResult<void>> pin(String roomId);

  /// Unpins a room from the top of the room list.
  ///
  /// Per-user preference, idempotent. The room reverts to its natural
  /// position (last-activity order) in the room list.
  Future<ChatResult<void>> unpin(String roomId);

  /// Hides a room from the user's room list.
  ///
  /// Per-user preference — the room is filtered out of [getUserRooms]
  /// results for this user only. Incoming messages still arrive and
  /// un-hide the room implicitly (the next list fetch will include it
  /// again). Use for WhatsApp-style "archive" UX.
  Future<ChatResult<void>> hide(String roomId);

  /// Unhides a room, making it visible again in the room list.
  ///
  /// Per-user preference, idempotent. Pair with [hide] for an
  /// archive/unarchive toggle.
  Future<ChatResult<void>> unhide(String roomId);

  /// Marks multiple rooms as read in a single request.
  ///
  /// Use for "mark all as read" on the room list — one round-trip
  /// instead of N. Each room is updated server-side to
  /// `lastReadAt = now`; the backend does NOT emit per-message read
  /// receipts to senders for batched marks (use
  /// [ChatMessagesApi.markRoomAsRead] when you need granular fan-out).
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds);

  /// Fetches unread counts for multiple rooms in a single request.
  ///
  /// Useful when rehydrating the room list from cache and you want
  /// fresh unread counters without re-fetching every room body.
  /// Returns one [UnreadRoom] per id; rooms with no unread messages
  /// are still included with a count of 0.
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(List<String> roomIds);

  /// Updates the cached room preview (last message, timestamp, type metadata, etc.)
  /// so it survives app restarts. Type-aware fields ([lastMessageType], [lastMessageMimeType],
  /// [lastMessageFileName], [lastMessageDurationMs], [lastMessageIsDeleted],
  /// [lastMessageReactionEmoji]) feed the WhatsApp-style preview rendered by `RoomTile`.
  ///
  /// Pure-local operation — does NOT hit the network. Called by the UI
  /// adapter every time a new message lands so the preview stays in
  /// sync with what `RoomTile` is rendering. Custom UIs that bypass
  /// the adapter must call this themselves to keep the cache truthful
  /// across restarts.
  Future<void> updateCachedRoomPreview(
    String roomId, {
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    bool? lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
  });
}

/// Room membership: invitations, removal, bans, and role management.
abstract class ChatMembersApi {
  /// Lists members of a room.
  ///
  /// Use to populate the "participants" screen or @-mention
  /// autocomplete. Paginated — for large groups iterate with
  /// [pagination]. Each [RoomUser] carries the user id plus role
  /// (member / admin / owner) and join timestamp.
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
  });

  /// Invites users to a room. The [mode] controls the membership flow:
  /// `invite` sends an invitation the user must accept;
  /// `inviteAndJoin` admin-adds them directly (skip accept step);
  /// `acceptInvitation` / `declineInvitation` resolve a pending invite
  /// for the current user (in those modes [userIds] must be the
  /// current user's id).
  ///
  /// WhatsApp-style group "add members" uses `inviteAndJoin`; an
  /// email-style "I want to invite you" flow uses `invite` + the
  /// invitee later calling with `acceptInvitation`. On success the
  /// backend emits `UserJoinedEvent` per added user so other members
  /// see the roster change in real time.
  ///
  /// ```dart
  /// await client.members.invite(
  ///   roomId,
  ///   userIds: newMemberIds,
  ///   mode: RoomUserMode.inviteAndJoin,
  /// );
  /// ```
  Future<ChatResult<void>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  });

  /// Removes a user from a room.
  ///
  /// Admin/owner only — backend returns 403 for non-privileged callers.
  /// Backend emits `UserLeftEvent` so the removed user and remaining
  /// members all see the change in real time. To self-leave use
  /// [leave] instead (avoids needing admin privileges on yourself).
  Future<ChatResult<void>> remove(String roomId, String userId);

  /// Current user leaves a room.
  ///
  /// Distinct from [remove] in that it never requires admin
  /// privileges. If the leaving user is the sole owner the backend
  /// promotes the next admin (or refuses the leave for 1-member
  /// rooms); use [delete] on the rooms API instead if you want to
  /// dissolve the room entirely.
  Future<ChatResult<void>> leave(String roomId);

  /// Changes a member's role (owner, admin, member).
  ///
  /// Admin/owner only. Use to promote a member to admin or demote an
  /// admin back to member. Transferring ownership is supported by
  /// passing `RoomRole.owner` to a second user — the previous owner is
  /// automatically demoted to admin. Backend emits
  /// `UserRoleChangedEvent` so other members see the change live.
  Future<ChatResult<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  );

  /// Bans a user from a room, optionally with a reason.
  ///
  /// Stronger than [remove] — the banned user cannot rejoin via
  /// [invite] until [unban] is called. Admin/owner only. The optional
  /// [reason] is stored server-side for moderator audit logs.
  Future<ChatResult<void>> ban(String roomId, String userId, {String? reason});

  /// Removes a ban from a user.
  ///
  /// Admin/owner only. After unbanning, the user must be re-invited
  /// via [invite] — unbanning alone does not restore membership.
  Future<ChatResult<void>> unban(String roomId, String userId);

  /// Mutes a specific user within a room.
  ///
  /// Admin/owner action — the muted user can still read the room but
  /// cannot send messages. Distinct from [ChatRoomsApi.mute] which is
  /// a per-user push preference. Idempotent.
  Future<ChatResult<void>> muteUser(String roomId, String userId);

  /// Unmutes a specific user within a room.
  ///
  /// Admin/owner action, idempotent. Restores send permission for the
  /// target user without changing their role or membership.
  Future<ChatResult<void>> unmuteUser(String roomId, String userId);
}

/// Messaging: send, edit, delete, receipts, typing, threads, reactions, pins, search, scheduling.
abstract class ChatMessagesApi {
  /// Fetches a single message by ID.
  ///
  /// Use when you have a message id (e.g. from a deep link or a push
  /// notification) and need the full message body. Prefer [list] when
  /// rendering a chat — fetching messages one at a time is wasteful.
  /// Returns a failure if the message was deleted or the user cannot
  /// see this room.
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId);

  /// Lists messages in a room with cursor-based pagination.
  ///
  /// Primary read path for the chat screen. The UI adapter calls this
  /// twice on chat open — once with `cacheFirst` for instant paint and
  /// once with `networkOnly` to reconcile with the server. For
  /// load-more (older messages) pass `pagination.before` set to the
  /// timestamp of the oldest message you already have. `unreadOnly`
  /// returns only the unread tail — useful for jump-to-unread flows.
  ///
  /// ```dart
  /// final res = await client.messages.list(
  ///   roomId,
  ///   pagination: ChatCursorPaginationParams(before: oldest.createdAt),
  /// );
  /// ```
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  });

  /// Sends a message via REST. Returns the created message with server-assigned ID.
  ///
  /// Use when you want a synchronous "did this land?" result — REST
  /// gives you the confirmed message in the same future. For optimistic
  /// UI prefer [sendViaWs] (which degrades to this on REST anyway).
  /// On success the backend fans out `NewMessageEvent` to all members
  /// including the sender's other devices.
  ///
  /// [tempId] is an optional optimistic ID from the UI layer, used to
  /// reconcile offline queue retries with the adapter's pending message
  /// tracking. [referencedMessageId] supports replies; [attachmentUrl]
  /// must already be uploaded via [ChatAttachmentsApi.upload].
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
  });

  /// Sends a message preferring the WebSocket transport when available.
  ///
  /// Transport-agnostic: when WS is connected the message is sent as a
  /// fire-and-forget WS frame and a synthetic [ChatMessage] with a temp id
  /// is returned (the server-confirmed message arrives later via
  /// `NewMessageEvent`). When WS is not connected (SSE fallback or fully
  /// disconnected) this degrades to the same code path as [send] over
  /// REST, returning the server-confirmed message.
  ///
  /// Preferred for chat-screen sends — the local optimistic bubble can
  /// be rendered immediately from the synthetic message and reconciled
  /// by id when the WS confirmation arrives.
  Future<ChatResult<ChatMessage>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  });

  /// Edits the text of an existing message.
  ///
  /// Allowed only for the sender; backend returns 403 otherwise. The
  /// edited message keeps its id and timestamp but the `editedAt`
  /// field is set, and the backend emits `MessageUpdatedEvent` so
  /// other members see the new text in real time. There is no
  /// edit-history surface — only the latest text is preserved.
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  });

  /// Deletes a message from a room.
  ///
  /// Senders can always delete their own messages; admins/owners can
  /// delete anyone's. The backend tombstones the message (it stays in
  /// the timeline marked as deleted, so reply chains keep working) and
  /// emits `MessageDeletedEvent`. Hard removal is not exposed via the
  /// SDK.
  Future<ChatResult<void>> delete(String roomId, String messageId);

  /// Sends a delivery or read receipt for a specific message.
  ///
  /// Use for per-message granularity (e.g. WhatsApp's blue ticks on
  /// the exact last-read message). For bulk "mark everything read"
  /// prefer [markRoomAsRead] — it's one round-trip and emits a single
  /// receipt event per recipient. Backend emits `receipt_updated` so
  /// the original sender's checkmarks flip in real time. For delivery
  /// confirmations prefer [markRoomAsDelivered] — the server treats a
  /// `delivered` receipt as a cursor anyway, and the dedicated call is
  /// consolidated by design.
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  });

  /// Confirms delivery of every message in [roomId] up to and including
  /// [lastDeliveredMessageId] (the delivered cursor — WhatsApp's double
  /// gray tick).
  ///
  /// Consolidated by design: one call per conversation covers any
  /// number of messages. The backend advances the per-user delivered
  /// cursor (a max-register, so re-confirming older messages is a
  /// silent no-op) and fans out a single `message_delivered` event to
  /// the other members only when the cursor actually moved. The UI
  /// adapter calls this automatically when `autoConfirmDelivery` is on;
  /// hosts driving ticks manually call it when their client has
  /// rendered/stored the messages.
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  });

  /// Marks all messages in a room as read, optionally up to a specific message.
  ///
  /// Preferred entry point for "user opened the chat" — single
  /// round-trip, updates room-level `lastReadAt`, and (when
  /// [lastReadMessageId] is provided) fans out `receipt_updated` so
  /// the original sender's last-read ticks advance. Omit
  /// [lastReadMessageId] for legacy behavior (only the room-level
  /// counter advances, no per-message event).
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  });

  /// Lists read receipts for all members of a room.
  ///
  /// Use to render the "read by" sheet on a sent message. Each
  /// [ReadReceipt] carries a user id and their last-read message id /
  /// timestamp; cross-reference with [ChatMembersApi.list] to render
  /// avatars. The list is unpaginated in practice (one row per
  /// member).
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  );

  /// Sends a typing indicator (start or stop) to a room.
  ///
  /// Fire-and-forget — when realtime is off (e.g. `manual` mode or
  /// disconnected) the SDK silently no-ops, so it is safe to call
  /// from a text-controller listener without checking connection
  /// state first. The UI adapter throttles to once every 3 seconds
  /// per room; custom UIs should throttle similarly to avoid flooding.
  ///
  /// ```dart
  /// client.messages.sendTyping(roomId);
  /// ```
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  });

  /// Fetches the thread (replies) for a given parent message.
  ///
  /// Use for Slack-style threaded reply panels. Cursor-paginated like
  /// [list]; the parent message itself is NOT included in the result —
  /// fetch separately via [get] (or render the cached copy) for the
  /// thread header.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    ChatCursorPaginationParams? pagination,
  });

  /// Gets aggregated reactions (emoji counts and user lists) for a message.
  ///
  /// Pass [cachePolicy] (preferred) to control cache behavior — typically
  /// `CachePolicy.networkOnly` to bypass cache and refetch. The
  /// [forceRefresh] bool is the legacy shape and is kept until 1.0 as a
  /// deprecated alias mapping to `CachePolicy.networkOnly`.
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    @Deprecated(
      'Use cachePolicy: CachePolicy.networkOnly instead. '
      'forceRefresh will be removed in 1.0.',
    )
    bool forceRefresh = false,
    CachePolicy? cachePolicy,
  });

  /// Removes the current user's reaction from a message.
  ///
  /// Only the calling user's reaction is removed — other users'
  /// reactions on the same message are unaffected. Backend emits
  /// `ReactionRemovedEvent` so the message's aggregated reaction
  /// counters update everywhere. Idempotent: calling when no
  /// reaction is present returns success.
  Future<ChatResult<void>> deleteReaction(String roomId, String messageId);

  /// Pins a message in a room so it appears in the pinned list.
  ///
  /// Visible to all members (not a per-user preference, unlike
  /// [ChatRoomsApi.pin]). Admin/owner gated by default — backends may
  /// loosen this via room config. Backend emits `MessagePinnedEvent`
  /// so other members see the pin in real time.
  Future<ChatResult<void>> pinMessage(String roomId, String messageId);

  /// Unpins a message from a room.
  ///
  /// Same permission model as [pinMessage]. Backend emits
  /// `MessageUnpinnedEvent`. Idempotent: unpinning a non-pinned
  /// message returns success.
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId);

  /// Lists all pinned messages in a room.
  ///
  /// Use to render the "pinned messages" panel. Each [MessagePin]
  /// carries the message id + pin timestamp + who pinned it; the
  /// full message body must be fetched via [get] if not already in
  /// the local cache.
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  });

  /// Full-text search of messages within a room.
  ///
  /// Server-side full-text search — scope is always a single room
  /// (cross-room search is not supported). Returns paginated results
  /// ranked by relevance and recency; pair with a per-room search bar
  /// that drives load-more via the returned `hasMore` flag.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    ChatPaginationParams? pagination,
  });

  /// Reports a message for moderation.
  ///
  /// Fire-and-forget from the user's perspective — the backend stores
  /// the report against the message for admin review via
  /// [listReports]. The reported user is NOT notified. Pass a free-form
  /// [reason] string; UIs typically expose a small fixed list (spam,
  /// abuse, …) and pass the chosen label.
  Future<ChatResult<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  });

  /// Lists reports filed against messages in a room.
  ///
  /// Admin/owner only — backend returns 403 otherwise. Use to drive a
  /// moderation queue. Each [MessageReport] carries the reporting
  /// user, target message, and reason.
  Future<ChatResult<ChatPaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    ChatPaginationParams? pagination,
  });

  /// Schedules a message to be sent at a future time.
  ///
  /// Backend stores the message and delivers it at [sendAt]. The
  /// returned [ScheduledMessage] carries the scheduled id which can
  /// be used with [cancelScheduled] before the delivery time. The
  /// message body is not visible to other members until it actually
  /// sends — there is no "scheduled by X" preview.
  Future<ChatResult<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  });

  /// Lists scheduled (not yet sent) messages in a room.
  ///
  /// Returns only the calling user's scheduled messages (no
  /// visibility into other users' scheduled queue). Already-sent
  /// messages drop out of this list — query the regular timeline via
  /// [list] for those.
  Future<ChatResult<ChatPaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  );

  /// Cancels a previously scheduled message.
  ///
  /// Only callable before [ScheduledMessage.sendAt]; trying to cancel
  /// after the message has been delivered returns a failure (the
  /// message is now a regular message and should be removed via
  /// [delete] instead).
  Future<ChatResult<void>> cancelScheduled(String roomId, String scheduledId);

  /// Clears chat history for the current user (client-side only).
  /// Marks all messages as read and hides messages sent before now.
  ///
  /// Per-user, local — does NOT delete messages from the server; other
  /// members continue to see the full history. The hide-before
  /// timestamp is persisted via the local cache and survives app
  /// restarts. Pair with [getClearedAt] to filter the timeline on
  /// subsequent loads.
  Future<ChatResult<void>> clearChat(String roomId);

  /// Returns the timestamp at which the user cleared this room's chat,
  /// or `ChatSuccess(null)` if the chat was never cleared. Wrapped in
  /// [ChatResult] so a cache I/O failure surfaces explicitly instead of
  /// being conflated with "never cleared".
  ///
  /// Pure-local read — cheap to call on every chat-screen open to
  /// decide whether to filter the rendered message list.
  Future<ChatResult<DateTime?>> getClearedAt(String roomId);
}

/// Contact list, direct messaging, typing indicators, and blocking.
abstract class ChatContactsApi {
  /// Lists the current user's contacts.
  ///
  /// Drives the contacts tab and the new-DM picker. [cachePolicy]
  /// defaults to `networkFirst`; the UI adapter passes `cacheFirst` for
  /// fast paint and re-issues `networkOnly` on pull-to-refresh. The
  /// returned [ChatContact] carries the contact's user id + display
  /// metadata; pair with [getPresence] for the online dot.
  Future<ChatResult<ChatPaginatedResponse<ChatContact>>> list({
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  });

  /// Adds a user to the contact list.
  ///
  /// One-sided: adding does NOT create a reciprocal entry on the other
  /// user. Idempotent — adding an already-present contact returns
  /// success. Backend emits `contact_added` so the contact appears on
  /// the user's other devices.
  Future<ChatResult<void>> add(String contactUserId);

  /// Removes a user from the contact list.
  ///
  /// One-sided removal; does NOT remove the underlying DM room (use
  /// [block] if you want messages to stop too). Idempotent. Backend
  /// emits `contact_removed` so other devices stay in sync.
  Future<ChatResult<void>> remove(String contactUserId);

  /// Sends a direct message to a contact (creates a 1:1 room if needed).
  ///
  /// Convenience wrapper around `rooms.create` + `messages.send` —
  /// the backend resolves or creates the 1:1 room behind the scenes
  /// and returns the message with its real id. Use this on the
  /// "first message in a DM that has never been opened" path; for
  /// subsequent messages in an existing DM prefer
  /// [ChatMessagesApi.sendViaWs] against the resolved room id (cheaper
  /// — no room-resolution round trip).
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  });

  /// Fetches direct message history with a contact.
  ///
  /// Equivalent to [ChatMessagesApi.list] against the resolved 1:1
  /// room. Use this when the caller only has the contact's user id
  /// (no room id yet). For paginated load-more pass
  /// `pagination.before` set to the oldest message timestamp.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    ChatCursorPaginationParams? pagination,
  });

  /// Fetches messages by conversation ID (the underlying 1:1 room ID).
  ///
  /// Use when you already hold the resolved 1:1 room id (e.g. from a
  /// previous call to [sendDirectMessage] which returned the room
  /// implicitly). Slightly cheaper than [getDirectMessages] because no
  /// contact→room lookup is needed.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>>
  getConversationMessages(
    String conversationId, {
    ChatCursorPaginationParams? pagination,
  });

  /// Gets the online presence of a contact.
  ///
  /// One-shot snapshot — for live updates subscribe to the
  /// `presence_updated` events on [ChatClient.events] or use
  /// [ChatPresenceApi.getAll] to bulk-refresh on app foreground.
  Future<ChatResult<ChatPresence>> getPresence(String contactUserId);

  /// Sends a typing indicator to a contact's DM conversation.
  ///
  /// Same fire-and-forget semantics as
  /// [ChatMessagesApi.sendTyping] — silent no-op when realtime is off
  /// or disconnected. Throttle on the caller side; the SDK does not
  /// throttle per-contact automatically.
  Future<ChatResult<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  });

  /// Blocks a user, hiding their messages and preventing contact.
  ///
  /// Two-way effect: incoming messages from [userId] are dropped on
  /// the server side, and the blocker can no longer DM the blocked
  /// user either. Backend emits `user_blocked` so the blocker's other
  /// devices update their contacts/DM lists. The blocked user is NOT
  /// notified.
  Future<ChatResult<void>> block(String userId);

  /// Unblocks a previously blocked user.
  ///
  /// Restores the ability to send/receive DMs but does NOT recreate
  /// historical DM rooms that were hidden during the block — call
  /// `rooms.create` for a fresh DM room if needed. Idempotent.
  Future<ChatResult<void>> unblock(String userId);

  /// Lists all blocked user IDs.
  ///
  /// Use to render a "Blocked users" settings screen or to filter
  /// search results. Returns only the user ids; cross-reference with
  /// [ChatUsersApi.get] to render names/avatars.
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  });
}

/// Presence management for the current user and contacts.
abstract class ChatPresenceApi {
  /// Gets the current user's own presence status.
  ///
  /// One-shot fetch — use when bootstrapping a settings screen that
  /// shows "your status". The realtime stream delivers updates after
  /// that via `presence_updated` events.
  Future<ChatResult<ChatPresence>> getOwn();

  /// Gets presence for the current user and all contacts in a single request.
  ///
  /// Preferred bulk read on app foreground to rehydrate the contacts
  /// tab's online dots in one round-trip. The returned
  /// [BulkPresenceResponse] carries one entry per contact + the
  /// caller's own entry — render directly without per-contact fetches.
  Future<ChatResult<BulkPresenceResponse>> getAll();

  /// Updates the current user's presence status and optional status text.
  ///
  /// Wire to the app lifecycle (online on resume, away on pause) and
  /// to a manual status picker. Backend emits `presence_updated` to
  /// all contacts so their online indicator flips in real time.
  /// [statusText] is the free-form WhatsApp-style "Hey there, I'm
  /// using…" line.
  Future<ChatResult<void>> update({
    required PresenceStatus status,
    String? statusText,
  });
}

/// File upload, download, and per-room attachment management.
abstract class ChatAttachmentsApi {
  /// Uploads binary data as an attachment. The onProgress callback reports upload progress.
  ///
  /// Two-step send pattern: upload first, then pass the returned URL
  /// to [ChatMessagesApi.send] as `attachmentUrl`. The UI adapter's
  /// `sendAttachment` helper bundles both steps and the
  /// `MessageType.attachment` metadata for you. [onProgress] fires on
  /// every chunk — useful for the progress bar; total may be -1 if
  /// the backend cannot determine the upload size up front.
  ///
  /// ```dart
  /// final upload = await client.attachments.upload(bytes, mimeType);
  /// final url = upload.dataOrNull?.url;
  /// ```
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  });

  /// Downloads an attachment's binary data by ID.
  ///
  /// Returns the raw bytes — wrap in `MemoryImage` for images, write
  /// to a temp file for documents, decode via `audioplayers` for
  /// voice notes. [metadata] is an optional opaque string the backend
  /// uses for signed-URL renegotiation in some deployments; leave
  /// null unless a previous SDK call gave you a value.
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? metadata,
    void Function(int received, int total)? onProgress,
  });

  /// Lists messages with attachments in a room.
  ///
  /// Use to render the "media + files" gallery in the room info
  /// panel. Returns full [ChatMessage] objects (not just attachment
  /// metadata) so you can render the original sender/timestamp under
  /// each item. Cursor-paginated like the regular message list.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  });

  /// Deletes an attachment message from a room.
  ///
  /// Same semantics as [ChatMessagesApi.delete] — sender or admin
  /// only, tombstones the message, emits `MessageDeletedEvent`. The
  /// underlying attachment bytes on the storage backend are reclaimed
  /// asynchronously by a background job, not synchronously by this
  /// call.
  Future<ChatResult<void>> deleteInRoom(String roomId, String messageId);
}
