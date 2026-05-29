import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/user.dart';

/// Manages the state of a single chat conversation: messages, typing indicators,
/// reactions, receipts, reply/edit state, and pagination.
///
/// Backed by a [ChangeNotifier] so widgets can rebuild via [ListenableBuilder].
class ChatController extends ChangeNotifier {
  ChatController({
    required List<ChatMessage> initialMessages,
    required ChatUser currentUser,
    List<ChatUser> otherUsers = const [],
    this.typingTimeout = const Duration(seconds: 7),
  }) : _messages = List<ChatMessage>.from(initialMessages),
       _currentUser = currentUser,
       _otherUsers = List<ChatUser>.from(otherUsers) {
    _sortMessages();
    _trimMessages();
    _rebuildIndex();
  }

  static const int maxMessages = 500;
  final Duration typingTimeout;

  final List<ChatMessage> _messages;
  final Map<String, int> _indexById = {};
  final ChatUser _currentUser;
  final List<ChatUser> _otherUsers;
  final Set<String> _typingUserIds = {};
  final Map<String, Timer> _typingTimers = {};
  String? _draft;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  final ScrollController scrollController = ScrollController();

  // Reactions: messageId -> {emoji -> count}
  final Map<String, Map<String, int>> _reactions = {};
  // User's own reactions: messageId -> {emoji}
  final Map<String, Set<String>> _userReactions = {};

  // Receipt statuses: messageId -> aggregated status (visible to UI).
  // For 1:1 chats the aggregate equals the single other user's state.
  // For groups, it's the WhatsApp-style aggregate: ✓✓-blue only when
  // every non-sender member has read.
  final Map<String, ReceiptStatus> _receiptStatuses = {};

  // Per-user breakdown driving the aggregate above. `_readBy[msg]` is
  // the set of userIds that have read `msg`; `_deliveredBy[msg]` covers
  // delivered+read (read implies delivered). Used by the group "read
  // by all" computation and by the propagation pass that flips older
  // messages from the same sender when a recipient reaches a high
  // water mark (a single backend event fans out to every prior msg).
  final Map<String, Set<String>> _readBy = {};
  final Map<String, Set<String>> _deliveredBy = {};

  // Pinned messages, latest first (per the backend's natural order).
  final List<MessagePin> _pinnedMessages = [];

  // Pending messages: tempId -> true (sending), false (failed)
  final Map<String, bool> _pendingMessages = {};
  // Map tempId -> serverId for optimistic replacement
  final Map<String, String> _tempToServerId = {};

  // Pagination
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _oldestMessageCursor;

  // Highlight (scroll-to-message)
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  // Draft state — see "Draft (lazy DM creation)" section below.
  bool _isDraft = false;
  String? _draftOtherUserId;
  String? _roomId;

  // Error state
  ChatError? _lastError;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String? get highlightedMessageId => _highlightedMessageId;
  ChatError? get lastError => _lastError;

  /// `true` while this controller represents a draft DM that has not been
  /// materialized server-side yet (no `roomId` assigned). See "Draft (lazy DM
  /// creation)" section below.
  bool get isDraft => _isDraft;

  /// The other user's id when [isDraft] is `true`. `null` once materialized
  /// (or for non-draft controllers).
  String? get draftOtherUserId => _draftOtherUserId;

  /// The server-side room id this controller is bound to. `null` while in
  /// draft state (see [isDraft]). The adapter sets this on creation
  /// (`getChatController`) and updates it on materialization
  /// (`_materializeDraft`); consumers can read it to route follow-up
  /// adapter calls without tracking the id separately.
  String? get roomId => _roomId;
  ChatUser get currentUser => _currentUser;
  List<ChatUser> get otherUsers => List.unmodifiable(_otherUsers);
  String? get draft => _draft;
  ChatMessage? get replyingTo => _replyingTo;
  ChatMessage? get editingMessage => _editingMessage;
  List<String> get typingUserIds => _typingUserIds.toList();
  Map<String, Map<String, int>> get reactions => Map.unmodifiable(_reactions);
  Map<String, Set<String>> get userReactions =>
      Map.unmodifiable(_userReactions);
  Map<String, ReceiptStatus> get receiptStatuses =>
      Map.unmodifiable(_receiptStatuses);
  List<MessagePin> get pinnedMessages => List.unmodifiable(_pinnedMessages);
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMoreMessages;
  String? get oldestMessageCursor => _oldestMessageCursor;

  // --- Messages ---

  void addMessage(ChatMessage message) {
    final existingIndex = _indexById[message.id];
    if (existingIndex != null) {
      _messages[existingIndex] = message;
      _sortMessages();
      _rebuildIndex();
      notifyListeners();
      return;
    }
    _messages.add(message);
    _sortMessages();
    _trimMessages();
    _rebuildIndex();
    notifyListeners();
  }

  void addMessages(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    for (final msg in messages) {
      final idx = _indexById[msg.id];
      if (idx != null) {
        _messages[idx] = msg;
      } else {
        _messages.add(msg);
      }
    }
    _sortMessages();
    _trimMessages();
    _rebuildIndex();
    notifyListeners();
  }

  void setMessages(List<ChatMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages);
    _sortMessages();
    _rebuildIndex();
    notifyListeners();
  }

  void updateMessage(ChatMessage message) {
    final index = _indexById[message.id];
    if (index == null) return;
    _messages[index] = message;
    notifyListeners();
  }

  void removeMessage(String messageId) {
    final index = _indexById[messageId];
    if (index == null) return;
    _messages.removeAt(index);
    _rebuildIndex();
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _indexById.clear();
    _reactions.clear();
    _userReactions.clear();
    _receiptStatuses.clear();
    _readBy.clear();
    _deliveredBy.clear();
    _pinnedMessages.clear();
    _pendingMessages.clear();
    _tempToServerId.clear();
    _draft = null;
    _replyingTo = null;
    _editingMessage = null;
    _typingUserIds.clear();
    _hasMoreMessages = true;
    _oldestMessageCursor = null;
    notifyListeners();
  }

  // --- Draft ---

  void setDraft(String? text, {bool notify = true}) {
    if (_draft == text) return;
    _draft = text;
    if (notify) {
      notifyListeners();
    }
  }

  // --- Reply / Edit ---

  void setReplyTo(ChatMessage? message) {
    _replyingTo = message;
    if (message != null) _editingMessage = null;
    notifyListeners();
  }

  void setEditingMessage(ChatMessage? message) {
    _editingMessage = message;
    if (message != null) _replyingTo = null;
    notifyListeners();
  }

  // --- Typing ---

  void setTyping(String userId, bool isTyping) {
    _typingTimers[userId]?.cancel();
    _typingTimers.remove(userId);

    if (isTyping) {
      _typingTimers[userId] = Timer(typingTimeout, () {
        _typingTimers.remove(userId);
        if (_typingUserIds.remove(userId)) {
          notifyListeners();
        }
      });
    }

    final changed = isTyping
        ? _typingUserIds.add(userId)
        : _typingUserIds.remove(userId);
    if (changed) notifyListeners();
  }

  // --- Users ---

  void setOtherUsers(List<ChatUser> users) {
    _otherUsers
      ..clear()
      ..addAll(users);
    notifyListeners();
  }

  // --- Draft (lazy DM creation) ---

  /// Marks this controller as a draft DM with [otherUserId]. While in draft
  /// state, the controller has no server-side room. The adapter
  /// (`openDirectMessageDraft`) sets this; consumers normally don't need to
  /// call it directly. Drafts materialize into a real room on the first
  /// successful send via `_OptimisticHandler.sendMessage`.
  void markAsDraft(String otherUserId) {
    _isDraft = true;
    _draftOtherUserId = otherUserId;
    notifyListeners();
  }

  /// Called by the adapter once the draft has been materialized server-side
  /// (a real `roomId` exists). Cleans the draft flags; the controller becomes
  /// indistinguishable from one created via `getChatController(roomId)`.
  void clearDraft() {
    if (!_isDraft) return;
    _isDraft = false;
    _draftOtherUserId = null;
    notifyListeners();
  }

  /// Binds the controller to [roomId]. Called by the adapter when a
  /// controller is created via `getChatController(roomId)` or when a draft
  /// is materialized (`_materializeDraft`). Consumers should NOT call this
  /// directly — read [roomId] instead.
  void setRoomId(String? roomId) {
    if (_roomId == roomId) return;
    _roomId = roomId;
    notifyListeners();
  }

  // --- Reactions ---

  void addReaction(String messageId, String emoji) {
    _reactions.putIfAbsent(messageId, () => {});
    _reactions[messageId]![emoji] = (_reactions[messageId]![emoji] ?? 0) + 1;
    notifyListeners();
  }

  void removeReaction(String messageId, String emoji) {
    final msgReactions = _reactions[messageId];
    if (msgReactions == null) return;
    final count = (msgReactions[emoji] ?? 0) - 1;
    if (count <= 0) {
      msgReactions.remove(emoji);
    } else {
      msgReactions[emoji] = count;
    }
    if (msgReactions.isEmpty) _reactions.remove(messageId);
    notifyListeners();
  }

  void clearReactions(String messageId) {
    if (_reactions.remove(messageId) != null) notifyListeners();
  }

  void setReactions(String messageId, Map<String, int> reactions) {
    if (reactions.isEmpty) {
      _reactions.remove(messageId);
    } else {
      _reactions[messageId] = Map.from(reactions);
    }
    notifyListeners();
  }

  void setUserReactions(String messageId, Set<String> emojis) {
    if (emojis.isEmpty) {
      _userReactions.remove(messageId);
    } else {
      _userReactions[messageId] = Set.from(emojis);
    }
    notifyListeners();
  }

  void addOwnReaction(String messageId, String emoji) {
    final existing = _userReactions[messageId];
    if (existing != null && existing.isNotEmpty) {
      for (final old in existing.toList()) {
        if (old != emoji) removeReaction(messageId, old);
      }
    }
    addReaction(messageId, emoji);
    (_userReactions[messageId] ??= {}).clear();
    _userReactions[messageId]!.add(emoji);
  }

  void removeOwnReaction(String messageId, String emoji) {
    removeReaction(messageId, emoji);
    _userReactions[messageId]?.remove(emoji);
    if (_userReactions[messageId]?.isEmpty ?? false) {
      _userReactions.remove(messageId);
    }
  }

  // --- Pending (optimistic sends) ---

  bool isPending(String messageId) => _pendingMessages[messageId] == true;
  bool isFailed(String messageId) => _pendingMessages[messageId] == false;
  Set<String> get failedMessageIds =>
      _pendingMessages.entries.where((e) => !e.value).map((e) => e.key).toSet();

  void markPending(String tempId) {
    _pendingMessages[tempId] = true;
    notifyListeners();
  }

  void markFailed(String tempId) {
    _pendingMessages[tempId] = false;
    notifyListeners();
  }

  void confirmSent(String tempId, ChatMessage serverMessage) {
    _pendingMessages.remove(tempId);
    _tempToServerId[tempId] = serverMessage.id;
    if (_tempToServerId.length > 100) {
      final excess = _tempToServerId.length - 50;
      final keysToRemove = _tempToServerId.keys.take(excess).toList();
      for (final k in keysToRemove) {
        _tempToServerId.remove(k);
      }
    }

    // Remove the temporary message
    final tempIndex = _indexById[tempId];
    if (tempIndex != null) {
      _messages.removeAt(tempIndex);
    }

    // Rebuild index after removal before upserting
    _rebuildIndex();

    // Upsert server message (may already exist if event arrived first)
    final existingIndex = _indexById[serverMessage.id];
    if (existingIndex != null) {
      _messages[existingIndex] = serverMessage;
    } else {
      _messages.add(serverMessage);
    }

    _sortMessages();
    _rebuildIndex();
    notifyListeners();
  }

  void removePending(String tempId) {
    _pendingMessages.remove(tempId);
    _tempToServerId.remove(tempId);
    removeMessage(tempId);
  }

  String? serverIdForTemp(String tempId) => _tempToServerId[tempId];

  // --- Receipts ---

  /// Records a receipt event for [messageId] attributed to [fromUserId]
  /// and recomputes the aggregated status visible in the UI.
  ///
  /// **DM semantics** (`otherUsers.length <= 1`): the aggregate matches
  /// the single peer's state directly — ✓ sent → ✓✓ delivered → ✓✓ read.
  ///
  /// **Group semantics** (WhatsApp): the bubble only flips to ✓✓-blue
  /// once every non-sender member has read. Until then it stays at
  /// "delivered" (or "sent") even if some members have read it.
  ///
  /// **High-water-mark propagation**: when [fromUserId] reads [messageId],
  /// the SDK implicitly marks every older message from the same sender
  /// as also read by [fromUserId] — backend keeps the wire small by only
  /// emitting the latest receipt, so the SDK fans it out locally and
  /// re-aggregates each affected row.
  ///
  /// [fromUserId] = `null` applies the receipt wholesale without
  /// per-user bookkeeping; behaves identically in 1:1 conversations.
  void updateReceipt(
    String messageId,
    ReceiptStatus status, {
    String? fromUserId,
  }) {
    if (fromUserId == null) {
      _receiptStatuses[messageId] = status;
      _propagateAggregated(messageId, status);
      notifyListeners();
      return;
    }

    _recordReceiptFor(messageId, status, fromUserId);

    // Propagate: any older message from the same sender that the reader
    // hadn't acknowledged yet is implicitly acknowledged at this level.
    if (status == ReceiptStatus.delivered || status == ReceiptStatus.read) {
      final reference = _messages.firstWhere(
        (m) => m.id == messageId,
        orElse: () => _absentReceiptReference,
      );
      if (!identical(reference, _absentReceiptReference)) {
        final referenceTs = reference.timestamp;
        final senderId = reference.from;
        for (final m in _messages) {
          if (m.id == messageId) continue;
          if (m.from != senderId) continue;
          if (m.timestamp.isAfter(referenceTs)) continue;
          _recordReceiptFor(m.id, status, fromUserId);
        }
      }
    }
    notifyListeners();
  }

  void _recordReceiptFor(
    String messageId,
    ReceiptStatus status,
    String fromUserId,
  ) {
    if (status == ReceiptStatus.delivered) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
    } else if (status == ReceiptStatus.read) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
      (_readBy[messageId] ??= <String>{}).add(fromUserId);
    }
    _receiptStatuses[messageId] = _aggregateStatus(messageId);
  }

  ReceiptStatus _aggregateStatus(String messageId) {
    final otherUserIds = _otherUsers.map((u) => u.id).toSet();
    final totalOthers = otherUserIds.length;
    if (totalOthers <= 1) {
      // 1:1 (or unresolved members): any read => read; any delivered => delivered.
      final readers = _readBy[messageId];
      if (readers != null && readers.isNotEmpty) return ReceiptStatus.read;
      final delivered = _deliveredBy[messageId];
      if (delivered != null && delivered.isNotEmpty) {
        return ReceiptStatus.delivered;
      }
      return ReceiptStatus.sent;
    }
    // Group: only mark as read once *every* other member has read.
    final readers = _readBy[messageId] ?? const <String>{};
    final readByAll =
        readers.length >= totalOthers && otherUserIds.every(readers.contains);
    if (readByAll) return ReceiptStatus.read;
    final delivered = _deliveredBy[messageId] ?? const <String>{};
    final deliveredToAll =
        delivered.length >= totalOthers &&
        otherUserIds.every(delivered.contains);
    if (deliveredToAll) return ReceiptStatus.delivered;
    // Some, but not all, members have ack'd — keep the bubble at sent
    // until at least delivered-by-all so the user sees the visual jump
    // exactly as WhatsApp renders it.
    return ReceiptStatus.sent;
  }

  // Legacy fan-out used only when the caller didn't supply a fromUserId.
  // Preserves the old "high water mark for all previous messages of the
  // same sender" behaviour for callers (and tests) still on the binary
  // API. Drops out cleanly when a per-user call arrives later.
  void _propagateAggregated(String messageId, ReceiptStatus status) {
    final reference = _messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => _absentReceiptReference,
    );
    if (identical(reference, _absentReceiptReference)) return;
    final referenceTs = reference.timestamp;
    final senderId = reference.from;
    for (final m in _messages) {
      if (m.id == messageId) continue;
      if (m.from != senderId) continue;
      if (m.timestamp.isAfter(referenceTs)) continue;
      final current = _receiptStatuses[m.id] ?? m.receipt;
      if (_rankReceipt(current) >= _rankReceipt(status)) continue;
      _receiptStatuses[m.id] = status;
    }
  }

  // Sentinel for `firstWhere` when the referenced message is no longer in
  // the controller's message list (e.g. evicted by cache). Lets us skip
  // the propagation pass without throwing.
  static final ChatMessage _absentReceiptReference = ChatMessage(
    id: '__noma_chat_absent_receipt_ref__',
    from: '',
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );

  static int _rankReceipt(ReceiptStatus? status) => switch (status) {
    null => 0,
    ReceiptStatus.sent => 1,
    ReceiptStatus.delivered => 2,
    ReceiptStatus.read => 3,
  };

  // --- Pinned messages ---

  void setPins(List<MessagePin> pins) {
    _pinnedMessages
      ..clear()
      ..addAll(pins);
    notifyListeners();
  }

  void addPin(MessagePin pin) {
    final existing = _pinnedMessages.indexWhere(
      (p) => p.messageId == pin.messageId,
    );
    if (existing != -1) {
      _pinnedMessages[existing] = pin;
    } else {
      _pinnedMessages.insert(0, pin);
    }
    notifyListeners();
  }

  void removePin(String messageId) {
    final before = _pinnedMessages.length;
    _pinnedMessages.removeWhere((p) => p.messageId == messageId);
    if (_pinnedMessages.length != before) notifyListeners();
  }

  void clearPins() {
    if (_pinnedMessages.isEmpty) return;
    _pinnedMessages.clear();
    notifyListeners();
  }

  bool isPinned(String messageId) =>
      _pinnedMessages.any((p) => p.messageId == messageId);

  // --- Pagination ---

  void setLoadingMore(bool loading) {
    if (_isLoadingMore == loading) return;
    _isLoadingMore = loading;
    notifyListeners();
  }

  void setPaginationState({required bool hasMore, String? cursor}) {
    _hasMoreMessages = hasMore;
    _oldestMessageCursor = cursor;
    notifyListeners();
  }

  void setError(ChatError error) {
    _lastError = error;
    notifyListeners();
  }

  void clearError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  // --- Lookup ---

  ChatMessage? getMessageById(String id) {
    final index = _indexById[id];
    return index != null ? _messages[index] : null;
  }

  // --- Highlight ---

  void highlightMessage(String messageId) {
    _highlightTimer?.cancel();
    _highlightedMessageId = messageId;
    notifyListeners();
    // 3s: long enough to land after a scroll-to-message animation
    // (search result → chat view) without parking the highlight
    // permanently. Previously 1500ms felt rushed when the target sat
    // mid-screen and the user was still tracking the row visually.
    _highlightTimer = Timer(const Duration(milliseconds: 3000), () {
      _highlightedMessageId = null;
      _highlightTimer = null;
      notifyListeners();
    });
  }

  // --- Internal ---

  void _sortMessages() {
    _messages.sort((a, b) {
      final cmp = a.timestamp.compareTo(b.timestamp);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
  }

  void _trimMessages() {
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
      _hasMoreMessages = true;
    }
  }

  void _rebuildIndex() {
    _indexById.clear();
    for (var i = 0; i < _messages.length; i++) {
      _indexById[_messages[i].id] = i;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    scrollController.dispose();
    super.dispose();
  }
}

/// Classification of a [ChatError]. Use it to decide whether to retry,
/// surface a validation message, or treat the error as opaque.
enum ChatErrorType { network, validation, server, timeout, unknown }

/// Lightweight error type emitted by UI controllers when SDK calls fail.
class ChatError {
  final String message;
  final ChatErrorType type;

  const ChatError({required this.message, this.type = ChatErrorType.unknown});

  @override
  String toString() => 'ChatError($type: $message)';
}
