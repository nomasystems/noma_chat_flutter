import '../core/result.dart';
import '../models/contact.dart';
import '../models/invited_room.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/room.dart';
import '../models/unread_room.dart';
import '../models/user.dart';

/// Contract for local data persistence in the chat SDK.
///
/// Every read/write method returns `Future<ChatResult<T>>` so cache I/O
/// failures (Hive disk full, decrypt mismatch, lock contention) surface
/// explicitly instead of being silently absorbed by the caller's
/// try/catch — or worse, conflated with "no data" (`null`). Callers
/// that want the legacy "best-effort" behaviour can `.dataOrNull` the
/// result; callers that want to react to failures can pattern-match.
///
/// Implementations may enforce a max messages per room limit via
/// eviction. [deleteRoom] must cascade to room details, messages,
/// unreads, and invited rooms. [dispose] is intentionally NOT wrapped
/// in [ChatResult] — it is a lifecycle hook called once at shutdown and
/// errors there are non-actionable.
abstract class ChatLocalDatasource {
  // Messages
  Future<ChatResult<void>> saveMessages(
    String roomId,
    List<ChatMessage> messages,
  );
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
    String? before,
    String? after,
  });
  Future<ChatResult<void>> updateMessage(String roomId, ChatMessage message);
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId);
  Future<ChatResult<void>> clearMessages(String roomId);
  Future<ChatResult<void>> setClearedAt(String roomId, DateTime timestamp);
  Future<ChatResult<DateTime?>> getClearedAt(String roomId);

  /// "Delete for me" persistence: a per-room set of message IDs the
  /// user explicitly hid via `messages.deleteLocally`. The network
  /// list endpoint has no concept of per-user hiding, so without
  /// this set the tombstone (or the deleted message) re-appears
  /// every time the chat is re-opened. Default implementations are
  /// no-ops so non-persistent datasources (memory) keep working,
  /// at the cost of losing the hidden set on app restart.
  Future<ChatResult<void>> hideMessageLocally(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
  Future<ChatResult<Set<String>>> getHiddenMessageIds(String roomId) async =>
      const ChatSuccess(<String>{});
  Future<ChatResult<void>> clearHiddenMessages(String roomId) async =>
      const ChatSuccess(null);

  // Pending/failed outgoing messages (best-effort persistence).
  // Default implementations are no-ops so alternate datasources stay compatible.
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async => const ChatSuccess(null);
  Future<ChatResult<List<PendingChatMessage>>> getPendingMessages(
    String roomId,
  ) async => const ChatSuccess(<PendingChatMessage>[]);
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
  Future<ChatResult<void>> clearPendingMessages(String roomId) async =>
      const ChatSuccess(null);

  // Rooms
  Future<ChatResult<void>> saveRooms(List<ChatRoom> rooms);
  Future<ChatResult<List<ChatRoom>>> getRooms();
  Future<ChatResult<ChatRoom?>> getRoom(String roomId);
  Future<ChatResult<void>> deleteRoom(String roomId);

  // Room details
  Future<ChatResult<void>> saveRoomDetail(RoomDetail detail);
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId);
  Future<ChatResult<void>> deleteRoomDetail(String roomId);

  // Users
  Future<ChatResult<void>> saveUsers(List<ChatUser> users);
  Future<ChatResult<List<ChatUser>>> getUsers();
  Future<ChatResult<ChatUser?>> getUser(String userId);
  Future<ChatResult<void>> deleteUser(String userId);

  // Contacts
  Future<ChatResult<void>> saveContacts(List<ChatContact> contacts);
  Future<ChatResult<List<ChatContact>>> getContacts();

  // Unreads & invitations
  Future<ChatResult<void>> saveUnreads(List<UnreadRoom> unreads);
  Future<ChatResult<List<UnreadRoom>>> getUnreads();
  Future<ChatResult<void>> saveInvitedRooms(List<InvitedRoom> invitedRooms);
  Future<ChatResult<List<InvitedRoom>>> getInvitedRooms();

  // Unreads (individual)
  Future<ChatResult<void>> deleteUnread(String roomId);

  // Reactions
  Future<ChatResult<void>> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  );
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  );
  Future<ChatResult<void>> deleteReactions(String roomId, String messageId);

  // Pins
  Future<ChatResult<void>> savePins(String roomId, List<MessagePin> pins);
  Future<ChatResult<List<MessagePin>>> getPins(String roomId);
  Future<ChatResult<void>> deletePin(String roomId, String messageId);

  // Read receipts
  Future<ChatResult<void>> saveReceipts(
    String roomId,
    List<ReadReceipt> receipts,
  );
  Future<ChatResult<List<ReadReceipt>>> getReceipts(String roomId);

  // Offline queue
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  );
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue();
  Future<ChatResult<void>> clearOfflineQueue();

  // Cache manager TTL timestamps. Persisted so `cacheFirst` survives
  // cold starts: without this, an empty in-memory `_timestamps` map
  // forces every `cacheFirst` resolve to fall through to network even
  // when the Hive box still holds fresh data. Stored in a single
  // meta entry (ISO-millis values) so reads are O(1) at boot.
  // Default impls are no-ops so alternate datasources stay compatible.
  Future<Map<String, DateTime>> loadCacheTimestamps() async =>
      const <String, DateTime>{};
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {}

  // Kicked-rooms registry — WhatsApp-parity. Local-only flag set
  // when the user receives a `user_left` event with themselves as
  // target and an `actorUserId` distinct from themselves. The room
  // gets retained on cold start even though the backend stops
  // returning it via `bulk_conversations` (they're no longer a
  // member). `unmarkKicked` runs on admin re-add (`user_joined`
  // with target = me) or when the user manually deletes the chat
  // via `ChatRoomOption.deleteKickedChat`. Default impls are
  // no-ops so alternate datasources stay compatible.
  Future<ChatResult<void>> markKicked(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<void>> unmarkKicked(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<Set<String>>> getKickedRoomIds() async =>
      const ChatSuccess(<String>{});

  // Lifecycle
  Future<ChatResult<void>> clear();

  /// Releases resources. Not wrapped in [ChatResult] — lifecycle errors at
  /// shutdown are non-actionable.
  Future<void> dispose();
}
