import 'dart:typed_data';

import '../cache/cache_policy.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/attachment.dart';
import '../models/contact.dart';
import '../models/health_status.dart';
import '../models/invite_result.dart';
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
import '../models/starred_message.dart';
import '../models/unread_room.dart';
import '../models/user.dart';
import '../models/user_rooms.dart';

part 'chat_attachments_api.dart';
part 'chat_contacts_api.dart';
part 'chat_messages_api.dart';
part 'chat_presence_api.dart';

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

  /// Number of operations currently sitting in the offline queue, waiting
  /// to be sent once the connection allows it.
  ///
  /// Drive a "pending" badge from this, or check it before calling
  /// [flushPendingOperations] to skip a redundant drain attempt. Clients
  /// without an offline queue configured always report `0`.
  int get pendingOperationCount;

  /// Forces an immediate drain attempt of the offline queue instead of
  /// waiting for the next reconnect.
  ///
  /// The queue already drains automatically on every connection (including
  /// the very first one after a cold start) — call this only for an
  /// on-demand retry, e.g. a manual "retry sending" affordance. A no-op on
  /// clients without an offline queue configured.
  Future<void> flushPendingOperations();

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

  /// Queues an attachment upload+send for automatic retry once the
  /// connection returns, instead of requiring the caller to re-drive the
  /// whole upload manually.
  ///
  /// Call this from an upload-failure branch — i.e. AFTER
  /// [ChatAttachmentsApi.upload] already failed — passing the failure that
  /// caused it as [causeFailure] so the client can decide whether it is
  /// safe to retry (a [NetworkFailure] or [TimeoutFailure] queues; a
  /// permanent failure like [ValidationFailure] or [AuthFailure] does
  /// not). [tempId] should match the optimistic bubble's id: when the
  /// queued retry eventually succeeds, [onOfflineMessageSent] fires with
  /// it so the UI can reconcile the bubble exactly like a queued text
  /// send. [referencedMessageId] carries the reply this attachment was
  /// answering, if any, so the replay preserves the quote instead of
  /// dropping it once the connection comes back. A no-op on clients
  /// without an offline queue configured ([ChatConfig.cacheConfig]
  /// `null`) — the caller has already shown its own failed/manual-retry
  /// state and there is nothing durable to fall back to.
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
    String? referencedMessageId,
  });

  /// Drops whatever the offline queue is holding for the optimistic row
  /// [tempId], returning how many operations went. `0` on clients without
  /// an offline queue configured, and on a row that was never queued.
  ///
  /// The counterpart to [enqueueOfflineAttachment] (and to the automatic
  /// enqueue every failed send does): call it whenever a failed bubble
  /// stops being the row the queue should deliver — the user discarded it,
  /// or a retry is re-driving the same file under a fresh id. Skipping it
  /// sends a message the user cancelled, or sends it twice, and neither
  /// can be taken back out of the room.
  int cancelOfflineSend(String tempId);
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

  /// Deletes the authenticated principal's **own** account permanently
  /// (`DELETE /users/me`).
  ///
  /// This is the robust default for GDPR right-to-erasure: it cannot
  /// target the wrong account because the server resolves "me" from the
  /// auth token, so no caller-supplied id is involved. Irreversible — the
  /// backend tombstones messages but removes the profile record; managed
  /// users belonging to this principal are cascaded out too.
  ///
  /// Prefer this over [delete] for self-service account deletion. After it
  /// succeeds you should tear the client down ([ChatClient.dispose]) and
  /// drive the host app back to its sign-out / onboarding flow, since the
  /// credential now points at a deleted account.
  ///
  /// ```dart
  /// final res = await client.users.deleteCurrentUser();
  /// res.fold(
  ///   (failure) => showError(failure),
  ///   (_) async {
  ///     await chat.dispose();
  ///     goToOnboarding();
  ///   },
  /// );
  /// ```
  Future<ChatResult<void>> deleteCurrentUser();

  /// Deletes a user permanently by id.
  ///
  /// **The [userId] MUST be the caller's own id.** The backend tightened
  /// `DELETE /users/{userId}` to own-account-only: passing any other id
  /// returns a 403 that surfaces as a [ForbiddenFailure] carrying the
  /// [ChatErrorTokens.cannotDeleteOtherUser] token. For self-service
  /// account deletion prefer [deleteCurrentUser], which targets
  /// `DELETE /users/me` and so can never hit the wrong account.
  ///
  /// Use for hard account deletion flows (GDPR right-to-erasure or
  /// admin tools that genuinely operate on their own principal).
  /// Irreversible — the backend tombstones messages but removes the
  /// profile record; managed users belonging to the deleted parent are
  /// cascaded out too.
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

  /// Lists managed users belonging to [parentId] (the parent user).
  ///
  /// Use to power an admin/owner list of "users I manage". Calls
  /// `GET /users/{parentId}/managed-users`, the path the backend treats as the
  /// source of truth for "users I manage". Always paginated; backend defaults
  /// apply when [pagination] is omitted. The caller must be the parent user;
  /// otherwise the backend rejects the request with a forbidden failure.
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManagedByParent(
    String parentId, {
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
  ///
  /// [forceGroup] — when `true`, a 2-member room is always reported as a
  /// `group` instead of collapsing into a 1:1 DM. Use it for "plan"-style
  /// rooms that happen to have two participants but should not render as a
  /// direct chat.
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
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

  /// Updates the current user's private room preferences in a single
  /// request and returns the merged server-side state.
  ///
  /// All preferences are per-user: they only affect the calling user and
  /// are invisible to other members. Pass only the fields you want to
  /// change — omitted parameters are left untouched server-side.
  ///
  /// - [muted] — `true` to silence notifications, `false` to unmute. For a
  ///   timed mute pass [muteUntil] instead (which implies `muted: true`).
  /// - [muteUntil] — mute only until that instant (WhatsApp-style 8h / 1
  ///   week timed mutes). Sent as an ISO-8601 string; the backend derives
  ///   `muted` by comparing it with the current time. Mutually exclusive
  ///   with an explicit [muted] value.
  /// - [pinned] — `true` to pin the room to the top of the list.
  /// - [hidden] — `true` to hide (archive) the room from [getUserRooms].
  ///
  /// On success the `roomDetail:<roomId>`, `rooms:all`, and `rooms:unread`
  /// TTL keys are invalidated so the next read reflects the change.
  ///
  /// This is the canonical preferences endpoint; [mute], [unmute], [pin],
  /// [unpin], [hide], and [unhide] are thin wrappers that delegate here.
  ///
  /// ```dart
  /// final res = await client.rooms.patchPreferences(
  ///   roomId,
  ///   pinned: true,
  ///   hidden: false,
  /// );
  /// switch (res) {
  ///   case ChatSuccess(:final data): print(data.pinned); // true
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  Future<ChatResult<RoomPreferences>> patchPreferences(
    String roomId, {
    bool? muted,
    DateTime? muteUntil,
    bool? pinned,
    bool? hidden,
  });

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
  /// [lastMessageIsSystem],
  /// [lastMessageReactionEmoji], [lastMessageReactionTargetText],
  /// [lastMessageReactionTargetType]) feed the WhatsApp-style preview
  /// `RoomTile` composes at paint time. [lastMessage] is the sender's own
  /// text and nothing else — never a label or a sentence composed for them.
  ///
  /// Passing [lastMessageType] states which message the row is now showing,
  /// so every field describing that message is replaced outright instead of
  /// falling back to what the row held before: a plain message landing after
  /// a photo clears the mime type rather than inheriting it and rendering
  /// as one. Calls that omit the type patch a single field (a receipt, a
  /// deletion) and leave the rest of the block alone.
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
    bool? lastMessageIsSystem,
    String? lastMessageReactionEmoji,
    String? lastMessageReactionTargetText,
    MessageType? lastMessageReactionTargetType,
  });

  /// Marks [roomId] deleted for the current user (WhatsApp "Delete chat"
  /// parity) — pure local, no network call. Persists through the local
  /// datasource the client itself was configured with
  /// (`ChatConfig.localDatasource`), mirroring how [ChatMessagesApi
  /// .getClearedAt]/`clearChat` survive a `ChatUiAdapter` built without its
  /// own `cache:` argument: as long as the client has a local datasource,
  /// `ChatRoomsController.delete` writing through here persists the marker
  /// even when the adapter's own cache is `null`. No-op (never throws) when
  /// no local datasource is configured.
  Future<ChatResult<void>> markRoomDeleted(String roomId);

  /// Clears a previous [markRoomDeleted] marker. Called by the resurrection
  /// path when a peer writes to a previously-deleted 1:1 room again — the
  /// room reappears (empty, `clearedAt` cutoff still in place). No-op if
  /// the room was never marked deleted or no local datasource is
  /// configured.
  Future<ChatResult<void>> clearRoomDeleted(String roomId);

  /// Every room id currently marked deleted for the current user. Used to
  /// filter deleted rooms out of a freshly (re)loaded list — e.g. on cold
  /// start, before any per-room resurrection event has had a chance to run.
  /// Empty when no local datasource is configured.
  Future<ChatResult<Set<String>>> getDeletedRoomIds();
}

/// Room membership: invitations, removal, bans, and role management.
abstract class ChatMembersApi {
  /// Lists members of a room.
  ///
  /// Use to populate the "participants" screen or @-mention
  /// autocomplete. Paginated — for large groups iterate with
  /// [pagination]. Each [RoomUser] carries the user id plus role
  /// (member / admin / owner).
  ///
  /// [expand] asks the backend to embed extra fields per row. Passing
  /// `[RoomMemberExpand.users]` (the recommended default for rendering a
  /// group roster) makes every [RoomUser] carry `displayName` + `avatarUrl`,
  /// so the screen renders names and avatars straight from this one response
  /// — no per-member `GET /users/{id}` round-trip (the N+1 it eliminates).
  /// Without [expand] each row is the bare `{userId, role}` and the
  /// expansion-only fields stay `null`; resolve them through the user cache
  /// as before. A name that stays unresolved renders as no name at all: the
  /// id is an identifier, never a label to show a reader.
  ///
  /// ```dart
  /// final res = await client.members.list(
  ///   roomId,
  ///   expand: const [RoomMemberExpand.users],
  /// );
  /// if (res case ChatSuccess(:final data)) {
  ///   for (final m in data.items) {
  ///     renderRow(m.displayName ?? '', m.avatarUrl);
  ///   }
  /// }
  /// ```
  ///
  /// [cachePolicy] selects the cache strategy — but **only the bare shape
  /// is cacheable**: the roster is read from and written to the local
  /// store solely when [pagination] is `null` AND [expand] is empty. Any
  /// other shape goes straight to the network whatever [cachePolicy] says.
  /// That is deliberate and load-bearing: one record per room cannot stand
  /// in for page 3 of a large group, and serving a bare cached roster to a
  /// caller that asked for `expand: [users]` would blank every name and
  /// avatar on screen.
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand,
    CachePolicy? cachePolicy,
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
  /// Resolves to an [InviteResult] with the per-user outcome — a successful
  /// call may still contain per-user failures (banned, already a member), so
  /// inspect [InviteResult.hasFailures] rather than assuming success. Pass
  /// [token] to join a public room by its invitation token. The backend does
  /// not accept a per-invite role; use [updateRole] afterwards.
  ///
  /// ```dart
  /// final res = await client.members.invite(
  ///   roomId,
  ///   userIds: newMemberIds,
  ///   mode: RoomUserMode.inviteAndJoin,
  /// );
  /// ```
  Future<ChatResult<InviteResult>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    String? token,
  });

  /// Joins the current user to a public room using an invitation [token].
  ///
  /// The growth-link counterpart of [invite]: where [invite] adds *other*
  /// users, this self-joins the authenticated user to [roomId] presenting
  /// the room's public token (the `publicToken` the backend returns when a
  /// public/invitable room is created, carried on [ChatRoom.publicToken]).
  /// Convenience wrapper over `invite(roomId, userIds: [self],
  /// mode: inviteAndJoin, token: token)`.
  ///
  /// Wire it to a deep-link handler: parse the incoming link with
  /// [ChatInviteLink.tryParse] and call this with the extracted room id and
  /// token. The backend still gates the join on ban/audience, so the
  /// returned [InviteResult] may report a per-user failure even on a 2xx.
  ///
  /// ```dart
  /// final link = ChatInviteLink.tryParse(incomingUri);
  /// if (link != null) {
  ///   await client.members.joinWithToken(link.roomId, token: link.token);
  /// }
  /// ```
  Future<ChatResult<InviteResult>> joinWithToken(
    String roomId, {
    required String token,
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
