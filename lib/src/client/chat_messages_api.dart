part of 'chat_client.dart';

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

  /// Lists messages in a room with bidirectional cursor pagination.
  ///
  /// Primary read path for the chat screen. The UI adapter calls this
  /// twice on chat open — once with `cacheFirst` for instant paint and
  /// once with `networkOnly` to reconcile with the server. Each page
  /// carries two opaque cursors: [ChatPaginatedResponse.prevCursor] anchored
  /// on the oldest message and [ChatPaginatedResponse.nextCursor] on the
  /// newest. To load older history pass `prevCursor` with
  /// `direction: ChatCursorDirection.older`; to catch up on newer messages
  /// pass `nextCursor` with `direction: ChatCursorDirection.newer`.
  /// `unreadOnly` returns only the unread tail — useful for jump-to-unread
  /// flows.
  ///
  /// ```dart
  /// final first = await client.messages.list(roomId);
  /// final older = await client.messages.list(
  ///   roomId,
  ///   pagination: ChatCursorPaginationParams(
  ///     cursor: first.dataOrThrow.prevCursor,
  ///     direction: ChatCursorDirection.older,
  ///   ),
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
  ///
  /// [clientMessageId] is an optional client-generated idempotency key
  /// (max 128 chars). When supplied, the backend makes the send idempotent
  /// over `(roomId, sender, clientMessageId)`: a POST retry that replays the
  /// same key returns the already-persisted message (the same `201` as a
  /// fresh send) instead of creating a duplicate. The backend round-trips
  /// the key inside the response `metadata.clientMessageId`; the SDK reads
  /// it back and surfaces it on [ChatMessage.clientMessageId] to reconcile
  /// the optimistic temporary message. The adapter and the offline queue
  /// generate and reuse one automatically; pass your own only for custom
  /// send flows. Recommended on mobile/unreliable networks.
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,

    /// Stable id of an attachment already uploaded via
    /// [ChatAttachmentsApi.upload] (its `attachmentId`). Echoed back on
    /// every read of this message so the UI can re-mint a fresh signed
    /// download URL on expiry instead of trusting the persisted
    /// [attachmentUrl] forever — see `SignedAttachmentUrlResolver`.
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
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
    String? attachmentId,
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

  /// Adds [emoji] as the current user's reaction to [messageId] via the
  /// canonical reactions endpoint (`POST
  /// /rooms/{roomId}/messages/{messageId}/reactions`).
  ///
  /// This is the only supported way to react: the dedicated endpoint models
  /// a reaction as a first-class sub-resource of the message instead of a
  /// synthetic reaction-typed message, so it never pollutes the timeline or
  /// the offline send queue. The backend emits `ReactionAddedEvent` so every
  /// member's aggregated counters update in real time. Idempotent — re-adding
  /// the same emoji the user already reacted with returns success.
  ///
  /// Removing the reaction is [deleteReaction].
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  });

  /// Removes the current user's reaction from a message.
  ///
  /// Pass [emoji] to remove a specific reaction (sends
  /// `DELETE /rooms/{roomId}/messages/{messageId}/reactions?emoji=…`) when
  /// the backend tracks more than one reaction per user; omit it to clear
  /// the user's reaction on the message wholesale (the historical
  /// single-reaction-per-user behaviour). Only the calling user's
  /// reaction is removed — other users' reactions on the same message are
  /// unaffected. Backend emits `ReactionRemovedEvent` so the message's
  /// aggregated reaction counters update everywhere. Idempotent: calling
  /// when no reaction is present returns success.
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  });

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

  /// Stars (bookmarks) a message for the current user only.
  ///
  /// A private, per-user bookmark — unlike [pinMessage], other members are
  /// not notified and do not see it. Idempotent: starring an
  /// already-starred message succeeds. Surface the starred set via
  /// [listStarred] (e.g. a "Starred messages" screen, WhatsApp-style).
  Future<ChatResult<void>> starMessage(String roomId, String messageId);

  /// Removes the current user's star from a message.
  ///
  /// Idempotent: unstarring a message that was not starred returns
  /// success.
  Future<ChatResult<void>> unstarMessage(String roomId, String messageId);

  /// Lists the current user's starred messages across all rooms, most
  /// recent first.
  ///
  /// Each [StarredMessage] is a lightweight reference (ids + timestamp);
  /// fetch the full body via its room when needed. Drives a "Starred
  /// messages" view; page with [ChatPaginationParams] and the returned
  /// `hasMore` / `totalCount`.
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> listStarred({
    ChatPaginationParams? pagination,
  });

  /// Full-text search of messages, server-side.
  ///
  /// Scope is controlled by [roomId]:
  ///
  /// - Omit [roomId] (or pass `null`) to search **globally** across every
  ///   room the caller belongs to. The backend scopes results to the
  ///   authenticated user's rooms — there is no way to reach messages in
  ///   rooms you are not a member of.
  /// - Pass a [roomId] to restrict the search to that single room, e.g. to
  ///   back a per-room search bar.
  ///
  /// Returns paginated results ranked by relevance and recency; drive
  /// load-more via the returned `hasMore` flag.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    String? roomId,
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

  /// Pure-local counterpart to [clearChat]: sets the clear-chat cutoff
  /// without also calling [markRoomAsRead] server-side. Used by
  /// `ChatRoomsController.delete` (WhatsApp "Delete chat"), which — unlike
  /// [clearChat] — must stay purely local and never fail on account of
  /// connectivity (deleting a chat has no server-side counterpart at all).
  /// No-op (never throws) when no local datasource is configured.
  Future<ChatResult<void>> setLocalClearedAt(String roomId, DateTime clearedAt);

  /// Writes [message] into the local message store for [roomId] with no
  /// server round-trip. Pure-local twin of [setLocalClearedAt], for the
  /// rows the server will never hand back: a message the backend rejected
  /// while the sender was shown it as sent has no other way of surviving
  /// a reopen, because every read path that could restore it is fed by
  /// the server.
  ///
  /// Written through the client surface — the same reason
  /// [markRoomDeleted] is — so the row persists for a `ChatUiAdapter`
  /// built without its own `cache:` argument, as long as the client has a
  /// local datasource. No-op (never throws) when it has none.
  Future<ChatResult<void>> saveLocalMessage(
    String roomId,
    ChatMessage message,
  ) => Future.value(const ChatSuccess<void>(null));

  /// Records [messageId] as hidden for this user in [roomId] ("delete for
  /// me") with no server round-trip. The backend has no per-user hide
  /// state, so without a durable marker the row — typically a tombstone —
  /// comes straight back on the next list fetch.
  ///
  /// Written through the client surface for the same reason as
  /// [saveLocalMessage]: the marker has to outlive a `ChatUiAdapter` built
  /// without its own `cache:` argument. No-op (never throws) when the
  /// client has no local datasource.
  Future<ChatResult<void>> hideLocalMessage(String roomId, String messageId) =>
      Future.value(const ChatSuccess<void>(null));
}
