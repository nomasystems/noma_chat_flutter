import 'dart:typed_data';

import '../_internal/cache/cache_policy.dart';
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
  Stream<ChatEvent> get events;

  /// Current connection state.
  ChatConnectionState get connectionState;

  /// Stream that emits whenever the connection state changes.
  Stream<ChatConnectionState> get stateChanges;

  /// Opens the real-time connection (WebSocket/SSE).
  Future<void> connect();

  /// Closes the real-time connection without clearing state.
  Future<void> disconnect();

  /// Notifies the server (via WebSocket) that the auth token has been rotated.
  /// Client must call this after refreshing the token while a real-time
  /// connection is open; if not connected, it is a no-op.
  Future<void> notifyTokenRotated();

  /// Disconnects and clears all local state (rooms, messages, contacts).
  Future<void> logout();

  /// Releases all resources. The client must not be used after this call.
  Future<void> dispose();

  /// Optional callback invoked by clients with an offline queue when a
  /// queued send completes after the connection is restored. The callback
  /// receives the room id, the original optimistic temp id, and the
  /// server-confirmed message. Clients that do not implement an offline
  /// queue may leave this as a no-op setter.
  ///
  /// Promoted to the abstract interface in 0.3.0 so the UI adapter no
  /// longer needs to `as` cast to a concrete implementation.
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  );
}

/// Server health and authentication checks.
abstract class ChatAuthApi {
  /// Returns the server health status including individual service checks.
  Future<Result<HealthStatus>> healthCheck();
}

/// User search, creation, profile updates, and managed-user operations.
abstract class ChatUsersApi {
  /// Searches users by display name.
  Future<Result<PaginatedResponse<ChatUser>>> search(
    String query, {
    PaginationParams? pagination,
  });

  /// Fetches a single user by ID.
  Future<Result<ChatUser>> get(String userId, {CachePolicy? cachePolicy});

  /// Creates a new user, optionally linked to external IDs.
  Future<Result<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
  });

  /// Updates profile fields for an existing user.
  Future<Result<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  });

  /// Deletes a user permanently.
  Future<Result<void>> delete(String userId);

  /// Finds a managed user by its external ID.
  Future<Result<ChatUser>> searchManaged({required String externalId});

  /// Creates managed users linked to the given external IDs.
  Future<Result<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  });

  /// Lists managed users belonging to a parent user.
  Future<Result<PaginatedResponse<ChatUser>>> getManaged(
    String userId, {
    PaginationParams? pagination,
  });

  /// Removes a managed user from its parent.
  Future<Result<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  });

  /// Gets the configuration of a managed user (webhooks, metadata).
  Future<Result<ManagedUserConfiguration>> getManagedConfig(String userId);

  /// Updates the configuration of a managed user.
  Future<Result<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  });
}

/// Room lifecycle: creation, listing, discovery, configuration, and user preferences.
abstract class ChatRoomsApi {
  /// Creates a new room with the given audience and optional initial members.
  Future<Result<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  });

  /// Lists the current user's rooms. Use type 'unread' to filter rooms with unread messages.
  Future<Result<UserRooms>> getUserRooms({
    String type = 'all',
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  });

  /// Searches public rooms by name or subject.
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    PaginationParams? pagination,
  });

  /// Fetches full room details including config, member count, and user role.
  Future<Result<RoomDetail>> get(String roomId, {CachePolicy? cachePolicy});

  /// Deletes a room permanently. Requires owner/admin role.
  Future<Result<void>> delete(String roomId);

  /// Updates room metadata (name, subject, avatar, custom data).
  Future<Result<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  });

  /// Mutes push notifications for a room.
  Future<Result<void>> mute(String roomId);

  /// Unmutes push notifications for a room.
  Future<Result<void>> unmute(String roomId);

  /// Pins a room to the top of the room list.
  Future<Result<void>> pin(String roomId);

  /// Unpins a room from the top of the room list.
  Future<Result<void>> unpin(String roomId);

  /// Hides a room from the user's room list.
  Future<Result<void>> hide(String roomId);

  /// Unhides a room, making it visible again in the room list.
  Future<Result<void>> unhide(String roomId);

  /// Marks multiple rooms as read in a single request.
  Future<Result<void>> batchMarkAsRead(List<String> roomIds);

  /// Fetches unread counts for multiple rooms in a single request.
  Future<Result<List<UnreadRoom>>> batchGetUnread(List<String> roomIds);

  /// Updates the cached room preview (last message, timestamp, type metadata, etc.)
  /// so it survives app restarts. Type-aware fields ([lastMessageType], [lastMessageMimeType],
  /// [lastMessageFileName], [lastMessageDurationMs], [lastMessageIsDeleted],
  /// [lastMessageReactionEmoji]) feed the WhatsApp-style preview rendered by `RoomTile`.
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
  Future<Result<PaginatedResponse<RoomUser>>> list(
    String roomId, {
    PaginationParams? pagination,
  });

  /// Adds users to a room. The mode controls whether they are invited or directly joined.
  Future<Result<void>> add(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  });

  /// Removes a user from a room.
  Future<Result<void>> remove(String roomId, String userId);

  /// Current user leaves a room.
  Future<Result<void>> leave(String roomId);

  /// Changes a member's role (owner, admin, member).
  Future<Result<void>> updateRole(String roomId, String userId, RoomRole role);

  /// Bans a user from a room, optionally with a reason.
  Future<Result<void>> ban(String roomId, String userId, {String? reason});

  /// Removes a ban from a user.
  Future<Result<void>> unban(String roomId, String userId);

  /// Mutes a specific user within a room.
  Future<Result<void>> muteUser(String roomId, String userId);

  /// Unmutes a specific user within a room.
  Future<Result<void>> unmuteUser(String roomId, String userId);
}

/// Messaging: send, edit, delete, receipts, typing, threads, reactions, pins, search, scheduling.
abstract class ChatMessagesApi {
  /// Fetches a single message by ID.
  Future<Result<ChatMessage>> get(String roomId, String messageId);

  /// Lists messages in a room with cursor-based pagination.
  Future<Result<PaginatedResponse<ChatMessage>>> list(
    String roomId, {
    CursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  });

  /// Sends a message via REST. Returns the created message with server-assigned ID.
  /// [tempId] is an optional optimistic ID from the UI layer, used to reconcile
  /// offline queue retries with the adapter's pending message tracking.
  Future<Result<ChatMessage>> send(
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

  /// Sends a message via WebSocket (fire-and-forget, no server response).
  Future<Result<void>> sendViaWs(
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
  Future<Result<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  });

  /// Deletes a message from a room.
  Future<Result<void>> delete(String roomId, String messageId);

  /// Sends a delivery or read receipt for a specific message.
  Future<Result<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  });

  /// Marks all messages in a room as read, optionally up to a specific message.
  Future<Result<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  });

  /// Lists read receipts for all members of a room.
  Future<Result<PaginatedResponse<ReadReceipt>>> getRoomReceipts(String roomId);

  /// Sends a typing indicator (start or stop) to a room.
  Future<Result<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  });

  /// Fetches the thread (replies) for a given parent message.
  Future<Result<PaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    CursorPaginationParams? pagination,
  });

  /// Gets aggregated reactions (emoji counts and user lists) for a message.
  ///
  /// Set [forceRefresh] to bypass cache and fetch from server.
  Future<Result<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    bool forceRefresh = false,
  });

  /// Removes the current user's reaction from a message.
  Future<Result<void>> deleteReaction(String roomId, String messageId);

  /// Pins a message in a room so it appears in the pinned list.
  Future<Result<void>> pinMessage(String roomId, String messageId);

  /// Unpins a message from a room.
  Future<Result<void>> unpinMessage(String roomId, String messageId);

  /// Lists all pinned messages in a room.
  Future<Result<PaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    PaginationParams? pagination,
  });

  /// Full-text search of messages within a room.
  Future<Result<PaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    PaginationParams? pagination,
  });

  /// Reports a message for moderation.
  Future<Result<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  });

  /// Lists reports filed against messages in a room.
  Future<Result<PaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    PaginationParams? pagination,
  });

  /// Schedules a message to be sent at a future time.
  Future<Result<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  });

  /// Lists scheduled (not yet sent) messages in a room.
  Future<Result<PaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  );

  /// Cancels a previously scheduled message.
  Future<Result<void>> cancelScheduled(String roomId, String scheduledId);

  /// Clears chat history for the current user (client-side only).
  /// Marks all messages as read and hides messages sent before now.
  Future<Result<void>> clearChat(String roomId);

  /// Returns the timestamp at which the user cleared this room's chat,
  /// or null if the chat was never cleared.
  Future<DateTime?> getClearedAt(String roomId);
}

/// Contact list, direct messaging, typing indicators, and blocking.
abstract class ChatContactsApi {
  /// Lists the current user's contacts.
  Future<Result<PaginatedResponse<ChatContact>>> list({
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  });

  /// Adds a user to the contact list.
  Future<Result<void>> add(String contactUserId);

  /// Removes a user from the contact list.
  Future<Result<void>> remove(String contactUserId);

  /// Sends a direct message to a contact (creates a 1:1 room if needed).
  Future<Result<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  });

  /// Fetches direct message history with a contact.
  Future<Result<PaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    CursorPaginationParams? pagination,
  });

  /// Fetches messages by conversation ID (the underlying 1:1 room ID).
  Future<Result<PaginatedResponse<ChatMessage>>> getConversationMessages(
    String conversationId, {
    CursorPaginationParams? pagination,
  });

  /// Gets the online presence of a contact.
  Future<Result<ChatPresence>> getPresence(String contactUserId);

  /// Sends a typing indicator to a contact's DM conversation.
  Future<Result<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  });

  /// Blocks a user, hiding their messages and preventing contact.
  Future<Result<void>> block(String userId);

  /// Unblocks a previously blocked user.
  Future<Result<void>> unblock(String userId);

  /// Lists all blocked user IDs.
  Future<Result<PaginatedResponse<String>>> listBlocked({
    PaginationParams? pagination,
  });
}

/// Presence management for the current user and contacts.
abstract class ChatPresenceApi {
  /// Gets the current user's own presence status.
  Future<Result<ChatPresence>> getOwn();

  /// Gets presence for the current user and all contacts in a single request.
  Future<Result<BulkPresenceResponse>> getAll();

  /// Updates the current user's presence status and optional status text.
  Future<Result<void>> update({
    required PresenceStatus status,
    String? statusText,
  });
}

/// File upload, download, and per-room attachment management.
abstract class ChatAttachmentsApi {
  /// Uploads binary data as an attachment. The onProgress callback reports upload progress.
  Future<Result<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  });

  /// Downloads an attachment's binary data by ID.
  Future<Result<Uint8List>> download(
    String attachmentId, {
    String? metadata,
    void Function(int received, int total)? onProgress,
  });

  /// Lists messages with attachments in a room.
  Future<Result<PaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    CursorPaginationParams? pagination,
  });

  /// Deletes an attachment message from a room.
  Future<Result<void>> deleteInRoom(String roomId, String messageId);
}
