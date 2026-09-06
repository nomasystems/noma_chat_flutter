part of 'chat_client.dart';

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
  ///
  /// If the recipient has blocked the sender the backend answers `204
  /// No Content`: the returned [ChatMessage] is synthesized locally
  /// with [ReceiptStatus.sent] and [ChatMessage.silentlyDropped] set to
  /// `true`. It must be rendered as an ordinary "sent" message — a
  /// block is invisible to the blocked sender, so a distinct state
  /// would give it away. See [ChatMessage.silentlyDropped].
  ///
  /// [clientMessageId] is the idempotency key for the send — same
  /// semantics as [ChatMessagesApi.send]: auto-generated when omitted,
  /// reused verbatim on offline-queue retries. Under the backend's
  /// `ack_mode = async` (the default) the returned message is a
  /// provisional echo ([ChatMessage.isProvisional] `true`) whose id does
  /// not match the stored message; correlate the authoritative
  /// `new_message` event via [ChatMessage.clientMessageId] and never use
  /// a provisional id for follow-up operations.
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  });

  /// Fetches direct message history with a contact.
  ///
  /// Equivalent to [ChatMessagesApi.list] against the resolved 1:1
  /// room. Use this when the caller only has the contact's user id
  /// (no room id yet). For paginated load-more pass
  /// [ChatPaginatedResponse.prevCursor] as the cursor with
  /// `direction: ChatCursorDirection.older`.
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
  /// Always sent over REST (`POST /contacts/{id}/activity`) — the
  /// backend's WS `typing` frame is room-scoped, so this is the only
  /// route that reaches the peer as a contact-activity event. Throttle
  /// on the caller side; the SDK does not throttle per-contact
  /// automatically.
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
