import '../../models/contact.dart';
import '../../models/invited_room.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/room.dart';
import '../../models/unread_room.dart';
import '../../models/user.dart';

/// Contract for local data persistence in the chat SDK.
///
/// Implementations may enforce a max messages per room limit via eviction.
/// [deleteRoom] must cascade to room details, messages, unreads, and invited
/// rooms. [dispose] releases resources — whether data persists on disk depends
/// on the implementation.
abstract class ChatLocalDatasource {
  // Messages
  Future<void> saveMessages(String roomId, List<ChatMessage> messages);
  Future<List<ChatMessage>> getMessages(
    String roomId, {
    int? limit,
    String? before,
    String? after,
  });
  Future<void> updateMessage(String roomId, ChatMessage message);
  Future<void> deleteMessage(String roomId, String messageId);
  Future<void> clearMessages(String roomId);
  Future<void> setClearedAt(String roomId, DateTime timestamp);
  Future<DateTime?> getClearedAt(String roomId);

  // Pending/failed outgoing messages (best-effort persistence).
  // Default implementations are no-ops so alternate datasources stay compatible.
  Future<void> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async {}
  Future<List<PendingChatMessage>> getPendingMessages(String roomId) async =>
      const [];
  Future<void> deletePendingMessage(String roomId, String messageId) async {}
  Future<void> clearPendingMessages(String roomId) async {}

  // Rooms
  Future<void> saveRooms(List<ChatRoom> rooms);
  Future<List<ChatRoom>> getRooms();
  Future<ChatRoom?> getRoom(String roomId);
  Future<void> deleteRoom(String roomId);

  // Room details
  Future<void> saveRoomDetail(RoomDetail detail);
  Future<RoomDetail?> getRoomDetail(String roomId);
  Future<void> deleteRoomDetail(String roomId);

  // Users
  Future<void> saveUsers(List<ChatUser> users);
  Future<List<ChatUser>> getUsers();
  Future<ChatUser?> getUser(String userId);
  Future<void> deleteUser(String userId);

  // Contacts
  Future<void> saveContacts(List<ChatContact> contacts);
  Future<List<ChatContact>> getContacts();

  // Unreads & invitations
  Future<void> saveUnreads(List<UnreadRoom> unreads);
  Future<List<UnreadRoom>> getUnreads();
  Future<void> saveInvitedRooms(List<InvitedRoom> invitedRooms);
  Future<List<InvitedRoom>> getInvitedRooms();

  // Unreads (individual)
  Future<void> deleteUnread(String roomId);

  // Reactions
  Future<void> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  );
  Future<List<AggregatedReaction>> getReactions(
    String roomId,
    String messageId,
  );
  Future<void> deleteReactions(String roomId, String messageId);

  // Pins
  Future<void> savePins(String roomId, List<MessagePin> pins);
  Future<List<MessagePin>> getPins(String roomId);
  Future<void> deletePin(String roomId, String messageId);

  // Read receipts
  Future<void> saveReceipts(String roomId, List<ReadReceipt> receipts);
  Future<List<ReadReceipt>> getReceipts(String roomId);

  // Offline queue
  Future<void> saveOfflineQueue(List<Map<String, dynamic>> operations);
  Future<List<Map<String, dynamic>>> getOfflineQueue();
  Future<void> clearOfflineQueue();

  // Lifecycle
  Future<void> clear();
  Future<void> dispose();
}
