import '../../core/result.dart';
import '../../models/contact.dart';
import '../../models/invited_room.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/room.dart';
import '../../models/unread_room.dart';
import '../../models/user.dart';
import '../../cache/local_datasource.dart';

/// In-memory implementation of [ChatLocalDatasource]. Data is lost when
/// the process exits. The `ChatResult` wrap returns `ChatSuccess` for every
/// operation — no I/O means nothing to fail on.
class MemoryChatLocalDatasource implements ChatLocalDatasource {
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, ChatRoom> _rooms = {};
  final Map<String, RoomDetail> _roomDetails = {};
  final Map<String, ChatUser> _users = {};
  List<ChatContact> _contacts = [];
  final Map<String, UnreadRoom> _unreads = {};
  List<InvitedRoom> _invitedRooms = [];
  List<Map<String, dynamic>> _offlineQueue = [];
  final Set<String> _kickedRoomIds = <String>{};
  final Map<String, Map<String, List<AggregatedReaction>>> _reactions = {};
  final Map<String, List<MessagePin>> _pins = {};
  final Map<String, List<ReadReceipt>> _receipts = {};
  final Map<String, List<PendingChatMessage>> _pendingMessages = {};
  final Map<String, DateTime> _clearedAt = {};
  Map<String, DateTime> _cacheManagerTimestamps = const <String, DateTime>{};

  @override
  Future<ChatResult<void>> saveMessages(
    String roomId,
    List<ChatMessage> messages,
  ) async {
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
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
    String? before,
    String? after,
  }) async {
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
      return ChatSuccess(filtered.sublist(0, limit));
    }
    return ChatSuccess(filtered);
  }

  @override
  Future<ChatResult<void>> updateMessage(
    String roomId,
    ChatMessage message,
  ) async {
    final messages = _messages[roomId];
    if (messages == null) return const ChatSuccess(null);
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      messages[idx] = message;
    }
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> deleteMessage(
    String roomId,
    String messageId,
  ) async {
    _messages[roomId]?.removeWhere((m) => m.id == messageId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> clearMessages(String roomId) async {
    _messages.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async {
    final list = _pendingMessages.putIfAbsent(roomId, () => []);
    list.removeWhere((p) => p.message.id == message.id);
    list.add(PendingChatMessage(message, isFailed: isFailed));
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<PendingChatMessage>>> getPendingMessages(
    String roomId,
  ) async {
    final list = _pendingMessages[roomId];
    if (list == null) return const ChatSuccess(<PendingChatMessage>[]);
    final sorted = [...list]
      ..sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));
    return ChatSuccess(List.unmodifiable(sorted));
  }

  @override
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) async {
    _pendingMessages[roomId]?.removeWhere((p) => p.message.id == messageId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> clearPendingMessages(String roomId) async {
    _pendingMessages.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveRooms(List<ChatRoom> rooms) async {
    for (final room in rooms) {
      _rooms[room.id] = room;
    }
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<ChatRoom>>> getRooms() async =>
      ChatSuccess(_rooms.values.toList());

  @override
  Future<ChatResult<ChatRoom?>> getRoom(String roomId) async =>
      ChatSuccess(_rooms[roomId]);

  @override
  Future<ChatResult<void>> deleteRoom(String roomId) async {
    _rooms.remove(roomId);
    _roomDetails.remove(roomId);
    _messages.remove(roomId);
    _unreads.remove(roomId);
    _reactions.remove(roomId);
    _pins.remove(roomId);
    _receipts.remove(roomId);
    _clearedAt.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveRoomDetail(RoomDetail detail) async {
    _roomDetails[detail.id] = detail;
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId) async =>
      ChatSuccess(_roomDetails[roomId]);

  @override
  Future<ChatResult<void>> deleteRoomDetail(String roomId) async {
    _roomDetails.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveUsers(List<ChatUser> users) async {
    for (final user in users) {
      _users[user.id] = user;
    }
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<ChatUser>>> getUsers() async =>
      ChatSuccess(_users.values.toList());

  @override
  Future<ChatResult<ChatUser?>> getUser(String userId) async =>
      ChatSuccess(_users[userId]);

  @override
  Future<ChatResult<void>> deleteUser(String userId) async {
    _users.remove(userId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveContacts(List<ChatContact> contacts) async {
    _contacts = List.of(contacts);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<ChatContact>>> getContacts() async =>
      ChatSuccess(_contacts);

  @override
  Future<ChatResult<void>> saveUnreads(List<UnreadRoom> unreads) async {
    for (final u in unreads) {
      _unreads[u.roomId] = u;
    }
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<UnreadRoom>>> getUnreads() async =>
      ChatSuccess(_unreads.values.toList());

  @override
  Future<ChatResult<void>> saveInvitedRooms(
    List<InvitedRoom> invitedRooms,
  ) async {
    _invitedRooms = invitedRooms;
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<InvitedRoom>>> getInvitedRooms() async =>
      ChatSuccess(_invitedRooms);

  @override
  Future<ChatResult<void>> deleteUnread(String roomId) async {
    _unreads.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) async {
    _offlineQueue = List.of(operations);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue() async =>
      ChatSuccess(List.of(_offlineQueue));

  @override
  Future<ChatResult<void>> clearOfflineQueue() async {
    _offlineQueue = [];
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> markKicked(String roomId) async {
    _kickedRoomIds.add(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> unmarkKicked(String roomId) async {
    _kickedRoomIds.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<Set<String>>> getKickedRoomIds() async =>
      ChatSuccess(Set<String>.of(_kickedRoomIds));

  // Reactions
  @override
  Future<ChatResult<void>> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  ) async {
    _reactions.putIfAbsent(roomId, () => {});
    _reactions[roomId]![messageId] = List.of(reactions);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) async {
    return ChatSuccess(_reactions[roomId]?[messageId] ?? const []);
  }

  @override
  Future<ChatResult<void>> deleteReactions(
    String roomId,
    String messageId,
  ) async {
    _reactions[roomId]?.remove(messageId);
    return const ChatSuccess(null);
  }

  // Pins
  @override
  Future<ChatResult<void>> savePins(
    String roomId,
    List<MessagePin> pins,
  ) async {
    _pins[roomId] = List.of(pins);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<MessagePin>>> getPins(String roomId) async {
    return ChatSuccess(_pins[roomId] ?? const []);
  }

  @override
  Future<ChatResult<void>> deletePin(String roomId, String messageId) async {
    _pins[roomId]?.removeWhere((p) => p.messageId == messageId);
    return const ChatSuccess(null);
  }

  // Read receipts
  @override
  Future<ChatResult<void>> saveReceipts(
    String roomId,
    List<ReadReceipt> receipts,
  ) async {
    _receipts[roomId] = List.of(receipts);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<List<ReadReceipt>>> getReceipts(String roomId) async {
    return ChatSuccess(_receipts[roomId] ?? const []);
  }

  @override
  Future<ChatResult<void>> clear() async {
    _messages.clear();
    _rooms.clear();
    _roomDetails.clear();
    _users.clear();
    _contacts = [];
    _unreads.clear();
    _invitedRooms = [];
    _offlineQueue = [];
    _kickedRoomIds.clear();
    _reactions.clear();
    _pins.clear();
    _receipts.clear();
    _clearedAt.clear();
    _cacheManagerTimestamps = const <String, DateTime>{};
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> setClearedAt(
    String roomId,
    DateTime timestamp,
  ) async {
    _clearedAt[roomId] = timestamp;
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) async {
    return ChatSuccess(_clearedAt[roomId]);
  }

  // In-memory mirror of the persistent "delete for me" set
  // (`hideMessageLocally` in `HiveChatDatasource`). Lives only for the
  // process lifetime — restart means hidden messages reappear. That's
  // fine for testing fixtures and for the no-cache mode where the
  // consumer already accepted in-memory-only state.
  final Map<String, Set<String>> _hiddenMessages = {};

  @override
  Future<ChatResult<void>> hideMessageLocally(
    String roomId,
    String messageId,
  ) async {
    (_hiddenMessages[roomId] ??= <String>{}).add(messageId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<Set<String>>> getHiddenMessageIds(String roomId) async {
    return ChatSuccess(_hiddenMessages[roomId] ?? const <String>{});
  }

  @override
  Future<ChatResult<void>> clearHiddenMessages(String roomId) async {
    _hiddenMessages.remove(roomId);
    return const ChatSuccess(null);
  }

  @override
  Future<Map<String, DateTime>> loadCacheTimestamps() async =>
      Map<String, DateTime>.of(_cacheManagerTimestamps);

  @override
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {
    _cacheManagerTimestamps = Map<String, DateTime>.of(timestamps);
  }

  @override
  Future<void> dispose() async {
    await clear();
  }
}
