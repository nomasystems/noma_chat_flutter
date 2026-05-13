import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:noma_chat/noma_chat.dart';

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

  // Receipt statuses: messageId -> status
  final Map<String, ReceiptStatus> _receiptStatuses = {};

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

  // Error state
  ChatError? _lastError;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String? get highlightedMessageId => _highlightedMessageId;
  ChatError? get lastError => _lastError;
  ChatUser get currentUser => _currentUser;
  List<ChatUser> get otherUsers => List.unmodifiable(_otherUsers);
  String? get draft => _draft;
  ChatMessage? get replyingTo => _replyingTo;
  ChatMessage? get editingMessage => _editingMessage;
  List<String> get typingUserIds => _typingUserIds.toList();
  Map<String, Map<String, int>> get reactions => Map.unmodifiable(_reactions);
  Map<String, Set<String>> get userReactions => Map.unmodifiable(_userReactions);
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
      _pendingMessages.entries
          .where((e) => !e.value)
          .map((e) => e.key)
          .toSet();

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

  void updateReceipt(String messageId, ReceiptStatus status) {
    _receiptStatuses[messageId] = status;
    notifyListeners();
  }

  // --- Pinned messages ---

  void setPins(List<MessagePin> pins) {
    _pinnedMessages
      ..clear()
      ..addAll(pins);
    notifyListeners();
  }

  void addPin(MessagePin pin) {
    final existing =
        _pinnedMessages.indexWhere((p) => p.messageId == pin.messageId);
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
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
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
