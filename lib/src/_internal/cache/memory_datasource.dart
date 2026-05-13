import '../../models/contact.dart';
import '../../models/invited_room.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/room.dart';
import '../../models/unread_room.dart';
import '../../models/user.dart';
import 'local_datasource.dart';

/// In-memory implementation of [ChatLocalDatasource]. Data is lost when the process exits.
class MemoryChatLocalDatasource implements ChatLocalDatasource {
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, ChatRoom> _rooms = {};
  final Map<String, RoomDetail> _roomDetails = {};
  final Map<String, ChatUser> _users = {};
  List<ChatContact> _contacts = [];
  final Map<String, UnreadRoom> _unreads = {};
  List<InvitedRoom> _invitedRooms = [];
  List<Map<String, dynamic>> _offlineQueue = [];
  final Map<String, Map<String, List<AggregatedReaction>>> _reactions = {};
  final Map<String, List<MessagePin>> _pins = {};
  final Map<String, List<ReadReceipt>> _receipts = {};
  final Map<String, List<PendingChatMessage>> _pendingMessages = {};

  @override
  Future<void> saveMessages(String roomId, List<ChatMessage> messages) async {
    final existing = _messages[roomId] ?? [];
    final merged = <String, ChatMessage>{};
    for (final m in existing) {
      merged[m.id] = m;
    }
    for (final m in messages) {
      merged[m.id] = m;
    }
    _messages[roomId] = merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<List<ChatMessage>> getMessages(String roomId,
      {int? limit, String? before, String? after}) async {
    final messages = _messages[roomId] ?? [];
    var filtered = messages;
    if (before != null) {
      final idx = messages.indexWhere((m) => m.id == before);
      if (idx >= 0) {
        filtered = messages.sublist(idx + 1);
      }
    }
    if (after != null) {
      final ts = DateTime.tryParse(after);
      if (ts != null) {
        filtered = filtered.where((m) => m.timestamp.isAfter(ts)).toList();
      }
    }
    if (limit != null && filtered.length > limit) {
      return filtered.sublist(0, limit);
    }
    return filtered;
  }

  @override
  Future<void> updateMessage(String roomId, ChatMessage message) async {
    final messages = _messages[roomId];
    if (messages == null) return;
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      messages[idx] = message;
    }
  }

  @override
  Future<void> deleteMessage(String roomId, String messageId) async {
    _messages[roomId]?.removeWhere((m) => m.id == messageId);
  }

  @override
  Future<void> clearMessages(String roomId) async {
    _messages.remove(roomId);
  }

  @override
  Future<void> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async {
    final list = _pendingMessages.putIfAbsent(roomId, () => []);
    list.removeWhere((p) => p.message.id == message.id);
    list.add(PendingChatMessage(message, isFailed: isFailed));
  }

  @override
  Future<List<PendingChatMessage>> getPendingMessages(String roomId) async {
    final list = _pendingMessages[roomId];
    if (list == null) return const [];
    final sorted = [...list]
      ..sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));
    return List.unmodifiable(sorted);
  }

  @override
  Future<void> deletePendingMessage(String roomId, String messageId) async {
    _pendingMessages[roomId]?.removeWhere((p) => p.message.id == messageId);
  }

  @override
  Future<void> clearPendingMessages(String roomId) async {
    _pendingMessages.remove(roomId);
  }

  @override
  Future<void> saveRooms(List<ChatRoom> rooms) async {
    for (final room in rooms) {
      _rooms[room.id] = room;
    }
  }

  @override
  Future<List<ChatRoom>> getRooms() async => _rooms.values.toList();

  @override
  Future<ChatRoom?> getRoom(String roomId) async => _rooms[roomId];

  @override
  Future<void> deleteRoom(String roomId) async {
    _rooms.remove(roomId);
    _roomDetails.remove(roomId);
    _messages.remove(roomId);
    _unreads.remove(roomId);
    _reactions.remove(roomId);
    _pins.remove(roomId);
    _receipts.remove(roomId);
    _clearedAt.remove(roomId);
  }

  @override
  Future<void> saveRoomDetail(RoomDetail detail) async {
    _roomDetails[detail.id] = detail;
  }

  @override
  Future<RoomDetail?> getRoomDetail(String roomId) async =>
      _roomDetails[roomId];

  @override
  Future<void> deleteRoomDetail(String roomId) async {
    _roomDetails.remove(roomId);
  }

  @override
  Future<void> saveUsers(List<ChatUser> users) async {
    for (final user in users) {
      _users[user.id] = user;
    }
  }

  @override
  Future<List<ChatUser>> getUsers() async => _users.values.toList();

  @override
  Future<ChatUser?> getUser(String userId) async => _users[userId];

  @override
  Future<void> deleteUser(String userId) async {
    _users.remove(userId);
  }

  @override
  Future<void> saveContacts(List<ChatContact> contacts) async {
    _contacts = List.of(contacts);
  }

  @override
  Future<List<ChatContact>> getContacts() async => _contacts;

  @override
  Future<void> saveUnreads(List<UnreadRoom> unreads) async {
    for (final u in unreads) {
      _unreads[u.roomId] = u;
    }
  }

  @override
  Future<List<UnreadRoom>> getUnreads() async => _unreads.values.toList();

  @override
  Future<void> saveInvitedRooms(List<InvitedRoom> invitedRooms) async {
    _invitedRooms = invitedRooms;
  }

  @override
  Future<List<InvitedRoom>> getInvitedRooms() async => _invitedRooms;

  @override
  Future<void> deleteUnread(String roomId) async {
    _unreads.remove(roomId);
  }

  @override
  Future<void> saveOfflineQueue(List<Map<String, dynamic>> operations) async {
    _offlineQueue = List.of(operations);
  }

  @override
  Future<List<Map<String, dynamic>>> getOfflineQueue() async =>
      List.of(_offlineQueue);

  @override
  Future<void> clearOfflineQueue() async {
    _offlineQueue = [];
  }

  // Reactions
  @override
  Future<void> saveReactions(
      String roomId, String messageId, List<AggregatedReaction> reactions) async {
    _reactions.putIfAbsent(roomId, () => {});
    _reactions[roomId]![messageId] = List.of(reactions);
  }

  @override
  Future<List<AggregatedReaction>> getReactions(
      String roomId, String messageId) async {
    return _reactions[roomId]?[messageId] ?? [];
  }

  @override
  Future<void> deleteReactions(String roomId, String messageId) async {
    _reactions[roomId]?.remove(messageId);
  }

  // Pins
  @override
  Future<void> savePins(String roomId, List<MessagePin> pins) async {
    _pins[roomId] = List.of(pins);
  }

  @override
  Future<List<MessagePin>> getPins(String roomId) async {
    return _pins[roomId] ?? [];
  }

  @override
  Future<void> deletePin(String roomId, String messageId) async {
    _pins[roomId]?.removeWhere((p) => p.messageId == messageId);
  }

  // Read receipts
  @override
  Future<void> saveReceipts(String roomId, List<ReadReceipt> receipts) async {
    _receipts[roomId] = List.of(receipts);
  }

  @override
  Future<List<ReadReceipt>> getReceipts(String roomId) async {
    return _receipts[roomId] ?? [];
  }

  @override
  Future<void> clear() async {
    _messages.clear();
    _rooms.clear();
    _roomDetails.clear();
    _users.clear();
    _contacts = [];
    _unreads.clear();
    _invitedRooms = [];
    _offlineQueue = [];
    _reactions.clear();
    _pins.clear();
    _receipts.clear();
    _clearedAt.clear();
  }

  final Map<String, DateTime> _clearedAt = {};

  @override
  Future<void> setClearedAt(String roomId, DateTime timestamp) async {
    _clearedAt[roomId] = timestamp;
  }

  @override
  Future<DateTime?> getClearedAt(String roomId) async {
    return _clearedAt[roomId];
  }

  @override
  Future<void> dispose() async => clear();
}
