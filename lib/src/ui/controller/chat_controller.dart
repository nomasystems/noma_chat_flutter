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
  // Secondary index for send reconciliation: under the backend's
  // ack_mode=async the optimistic temp row, the provisional REST echo and
  // the authoritative `new_message` event all describe the same logical
  // message under DIFFERENT ids, correlated only by clientMessageId.
  final Map<String, int> _indexByClientMessageId = {};
  final ChatUser _currentUser;
  final List<ChatUser> _otherUsers;

  // Whether this conversation is a group. `null` means "not told yet" — the
  // controller then infers it from `_otherUsers.length`, which is only safe
  // once member hydration has completed. While members are still loading a
  // group can momentarily look like a 1:1 (0–1 known members) and the receipt
  // aggregate would wrongly flip to "read by all". Setting this flag
  // explicitly (via [setIsGroup]) pins the group/1:1 decision so the aggregate
  // never degrades during hydration.
  bool? _isGroup;
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
  //
  // Written ONLY through [_setReceipt] (monotonic) and reset ONLY through
  // [_clearReceipts] or [_revokeReceiptFor]. Assigning into it directly
  // reintroduces the ✓✓ → ✓ downgrade this indirection exists to prevent.
  final Map<String, ReceiptStatus> _receiptStatuses = {};

  // Ids whose receipt advanced and whose row has not been written back to
  // the cache yet. The map above dies with the process; `ChatMessage.receipt`
  // is what survives it, so every advance is mirrored onto the message
  // object and queued here for the adapter to persist — see
  // [drainReceiptUpdates].
  final Set<String> _receiptDirty = {};

  // Ids whose receipt was derived from evidence that dies with this
  // session — a peer's whole-room read, which describes its own extent by
  // a confirmation time and by nothing else. The mark is shown like any
  // other, but the row never leaves through [drainReceiptUpdates], for
  // ANY consumer: the cache merges receipts upward and can never lower a
  // stored one, so a value that cannot be re-derived on the next cold
  // start must not become permanent. Fed by [updateReceipt]'s
  // `persistable: false`.
  //
  // An id stays here for as long as its per-user breakdown does: every
  // later aggregate for that row is computed from the same [_readBy] /
  // [_deliveredBy] entries and so rests on the same evidence, however
  // well-traced whatever raised it was. [_clearReceipts] and
  // [_revokeReceiptFor], which drop that breakdown, drop this with it.
  final Set<String> _heldBackReceipts = {};

  // Per-user breakdown driving the aggregate above. `_readBy[msg]` is
  // the set of userIds that have read `msg`; `_deliveredBy[msg]` covers
  // delivered+read (read implies delivered). Used by the group "read
  // by all" computation and by the propagation pass that flips older
  // messages from the same sender when a recipient reaches a high
  // water mark (a single backend event fans out to every prior msg).
  final Map<String, Set<String>> _readBy = {};
  final Map<String, Set<String>> _deliveredBy = {};

  // Server-assigned seqs of messages, learned from `message_acked`
  // events. Enables numeric coverage checks when a delivered cursor
  // carries a seq (live path); messages without a known seq fall back
  // to conversation-order comparison against the cursor message.
  final Map<String, int> _seqByMessageId = {};

  // Per-user delivered cursors (max-registers). Each entry doubles as
  // the stash for cursors whose message is not loaded yet — cursors are
  // re-applied after [setMessages]/[addMessages], which is idempotent.
  final Map<String, ({String messageId, int? seq})> _deliveredCursors = {};

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

  /// `true` while [ChatMessagesController.load]'s initial cache+network
  /// fetch is in flight for this room. Starts `false` — a controller that
  /// [load] never touches (a draft DM, or one built directly by a
  /// consumer/test without going through the adapter) has nothing pending
  /// and should render its real empty state immediately rather than spin
  /// forever. [load] flips this to `true` synchronously (before its first
  /// `await`), so a host that calls `getChatController` then `messages.load`
  /// back-to-back in `initState` (the SDK's own wiring) never renders a
  /// frame with the flag still `false` while a fetch is genuinely in flight.
  bool _isLoadingInitial = false;

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

  /// `true` until the initial [ChatMessagesController.load] for this room
  /// resolves (cache and network phases both settled). Drives `ChatView`'s
  /// loading-vs-empty distinction: the empty state only renders once this
  /// is `false` and [messages] is still empty, so a room with no cached
  /// history doesn't flash "No messages" for the round-trip to the server.
  bool get isLoadingInitial => _isLoadingInitial;
  bool get hasMoreMessages => _hasMoreMessages;

  /// Opaque older-history cursor: the [ChatPaginatedResponse.prevCursor] of the
  /// most recent page loaded. Pass it back with
  /// `direction: ChatCursorDirection.older` to fetch the next older page.
  String? get oldestMessageCursor => _oldestMessageCursor;

  // --- Messages ---

  void addMessage(ChatMessage message) {
    final existingIndex = _existingIndexFor(message);
    if (existingIndex != null) {
      final replaced = _messages[existingIndex];
      if (_keepExistingOverProvisional(replaced, message)) return;
      _messages[existingIndex] = _mergeReceiptInto(message, replaced);
      if (replaced.id != message.id) {
        _reconcileReplacedId(replaced.id, message.id);
      }
      _sortMessages();
      _rebuildIndex();
      notifyListeners();
      return;
    }
    _messages.add(_mergeReceiptInto(message));
    _sortMessages();
    _trimMessages();
    _rebuildIndex();
    notifyListeners();
  }

  void addMessages(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    for (final msg in messages) {
      final idx = _existingIndexFor(msg);
      if (idx != null) {
        final replaced = _messages[idx];
        if (_keepExistingOverProvisional(replaced, msg)) continue;
        _messages[idx] = _mergeReceiptInto(msg, replaced);
        if (replaced.id != msg.id) _reconcileReplacedId(replaced.id, msg.id);
      } else {
        _messages.add(_mergeReceiptInto(msg));
      }
    }
    _sortMessages();
    _trimMessages();
    _rebuildIndex();
    _reapplyDeliveredCursors();
    notifyListeners();
  }

  /// Resolves the list slot [message] should land in: by id first, then —
  /// for own sends carrying a [ChatMessage.clientMessageId] — by that key,
  /// so the authoritative event message REPLACES the optimistic temp row
  /// or the ack_mode=async provisional echo instead of duplicating it.
  int? _existingIndexFor(ChatMessage message) {
    final byId = _indexById[message.id];
    if (byId != null) return byId;
    final cmid = message.clientMessageId;
    return cmid != null ? _indexByClientMessageId[cmid] : null;
  }

  /// `true` when the incoming [message] is a provisional echo of a row the
  /// controller already holds in authoritative form — the `new_message`
  /// event beat the REST 201 echo. The stored row's real id must win.
  bool _keepExistingOverProvisional(ChatMessage existing, ChatMessage message) {
    if (!message.isProvisional) return false;
    if (existing.isProvisional) return false;
    if (existing.id == message.id) return false;
    _reconcileReplacedId(message.id, existing.id);
    return true;
  }

  /// Migrates local bookkeeping when a row's id changes in place — the
  /// optimistic temp row (or an ack_mode=async provisional echo) got
  /// replaced by the authoritative message reconciled via clientMessageId.
  /// Clears the vanished id's pending/failed mark (the send is confirmed
  /// by definition once the event carries it) and re-points temp→server
  /// mappings at the authoritative id so [serverIdForTemp] keeps working.
  void _reconcileReplacedId(String oldId, String newId) {
    _pendingMessages.remove(oldId);
    _tempToServerId[oldId] = newId;
    for (final key in _tempToServerId.keys.toList()) {
      if (_tempToServerId[key] == oldId) _tempToServerId[key] = newId;
    }
  }

  void setMessages(List<ChatMessage> messages) {
    final merged = [
      for (final msg in messages)
        _mergeReceiptInto(msg, getMessageById(msg.id)),
    ];
    _messages
      ..clear()
      ..addAll(merged);
    _sortMessages();
    _rebuildIndex();
    _reapplyDeliveredCursors();
    notifyListeners();
  }

  void updateMessage(ChatMessage message) {
    final index = _indexById[message.id];
    if (index == null) return;
    _messages[index] = _mergeReceiptInto(message, _messages[index]);
    notifyListeners();
  }

  /// Flips the per-user starred flag on [messageId] in place. No-op when the
  /// message isn't loaded or the flag already matches. Drives the in-bubble
  /// star badge optimistically before the backend round-trip resolves.
  void setMessageStarred(String messageId, bool starred) {
    final index = _indexById[messageId];
    if (index == null) return;
    final msg = _messages[index];
    if (msg.isStarred == starred) return;
    _messages[index] = msg.copyWith(isStarred: starred);
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
    _indexByClientMessageId.clear();
    _reactions.clear();
    _userReactions.clear();
    _clearReceipts();
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

  /// Whether this conversation is a group, as resolved so far. Returns the
  /// explicitly-set value when known (see [setIsGroup]); otherwise infers it
  /// from the number of known other members.
  bool get isGroup => _isGroup ?? _otherUsers.length > 1;

  /// Pins whether this conversation is a group, independent of how many
  /// members have been hydrated yet. The adapter sets this from the room's
  /// type (`RoomListItem.isGroup`) as soon as the chat opens, so receipt
  /// aggregation knows a group is a group even before its member list loads.
  /// Recomputes every visible receipt because the group/1:1 distinction
  /// changes the "read by all" rule.
  void setIsGroup(bool value) {
    if (_isGroup == value) return;
    _isGroup = value;
    if (_recomputeAllReceipts()) notifyListeners();
  }

  void setOtherUsers(List<ChatUser> users) {
    final prevCount = _otherUsers.length;
    _otherUsers
      ..clear()
      ..addAll(users);
    // Member hydration changes the divisor used by the group "read by all"
    // computation, so recompute the aggregate whenever the count moves.
    // Without this a group that opened with an incomplete member list stays
    // stuck on whatever status the wrong divisor produced.
    if (_otherUsers.length != prevCount) {
      _recomputeAllReceipts();
    }
    notifyListeners();
  }

  /// Re-derives every cached receipt aggregate from the per-user breakdown.
  /// Only advances statuses: a reclassification (group/1:1) or a roster that
  /// shrank must never walk a bubble back down. Returns `true` when at least
  /// one visible status changed.
  bool _recomputeAllReceipts() {
    var changed = false;
    for (final entry in {..._readBy.keys, ..._deliveredBy.keys}.toList()) {
      if (_setReceipt(entry, _aggregateStatus(entry))) changed = true;
    }
    return changed;
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
    _revokeReceiptFor(tempId);
    notifyListeners();
  }

  void markFailed(String tempId) {
    _pendingMessages[tempId] = false;
    _revokeReceiptFor(tempId);
    notifyListeners();
  }

  /// `true` while [messageId] names an optimistic row whose send has not
  /// been confirmed — still in flight ([markPending]) or given up on
  /// ([markFailed]).
  ///
  /// Such a row exists on this device only: the server never accepted it,
  /// so nobody can have received or read it, and its temporary id is not
  /// one any peer cursor can legitimately refer to. Receipts must
  /// therefore stop at its door — see [_setReceipt].
  bool _isUnsent(String messageId) => _pendingMessages.containsKey(messageId);

  /// Erases every trace of a receipt for [messageId]: the aggregate, the
  /// per-user breakdown, the stamp on the row itself and its slot in the
  /// write-back queue.
  ///
  /// [_setReceipt] refuses unsent rows, so this only matters for the
  /// window BEFORE a row is declared unsent — a rehydrated pending row
  /// reaches the list through [addMessage] and is marked failed a step
  /// later, and [_mergeReceiptInto] can stamp it in between if it lands on
  /// a slot a confirmed row already occupied. Declaring the row unsent
  /// revokes that stamp instead of letting it reach the cache as history.
  void _revokeReceiptFor(String messageId) {
    _receiptStatuses.remove(messageId);
    _readBy.remove(messageId);
    _deliveredBy.remove(messageId);
    _receiptDirty.remove(messageId);
    _heldBackReceipts.remove(messageId);
    final index = _indexById[messageId];
    if (index == null) return;
    final msg = _messages[index];
    if (msg.receipt == null) return;
    _messages[index] = msg.copyWith(receipt: null);
  }

  void confirmSent(String tempId, ChatMessage serverMessage) {
    _pendingMessages.remove(tempId);

    // Remove the temporary message
    final tempIndex = _indexById[tempId];
    if (tempIndex != null) {
      _messages.removeAt(tempIndex);
    }

    // Rebuild index after removal before upserting
    _rebuildIndex();

    // Upsert the server message. Resolve by id first, then by
    // clientMessageId: under ack_mode=async the authoritative
    // `new_message` event can land BEFORE this echo, in which case the
    // row already exists under its real id and the provisional echo must
    // not add a duplicate — the event row's id wins.
    //
    // The upsert goes through [_mergeReceiptInto] like every other write
    // to [_messages]. A send confirmation is a REST echo: it knows the
    // message was accepted and nothing more, so it carries `sent` at best
    // (`ChatUiAdapter._ensureSentReceipt`). Assigned raw it would walk a
    // row the event stream had already advanced back down to one tick —
    // invisibly for the bundled list, which reads [receiptStatuses] first,
    // but plainly for any host rendering `ChatMessage.receipt`.
    var confirmedId = serverMessage.id;
    final existingIndex = _existingIndexFor(serverMessage);
    if (existingIndex != null) {
      final existing = _messages[existingIndex];
      if (_keepExistingOverProvisional(existing, serverMessage)) {
        confirmedId = existing.id;
      } else {
        _messages[existingIndex] = _mergeReceiptInto(serverMessage, existing);
        if (existing.id != serverMessage.id) {
          _reconcileReplacedId(existing.id, serverMessage.id);
        }
      }
    } else {
      _messages.add(_mergeReceiptInto(serverMessage));
    }

    _tempToServerId[tempId] = confirmedId;
    if (_tempToServerId.length > 100) {
      final excess = _tempToServerId.length - 50;
      final keysToRemove = _tempToServerId.keys.take(excess).toList();
      for (final k in keysToRemove) {
        _tempToServerId.remove(k);
      }
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
  ///
  /// [persistable] = `false` declares the receipt derived from evidence
  /// that cannot be re-checked once this session ends. It is applied and
  /// rendered like any other, but every row it advances — including the
  /// ones reached by the propagation above — is withheld from
  /// [drainReceiptUpdates] from then on, so no consumer can write it to
  /// the cache, where receipts only ever merge upward. The room-open
  /// rehydration passes it for a peer's whole-room read: that row names no
  /// cursor message, and its confirmation time is not one.
  void updateReceipt(
    String messageId,
    ReceiptStatus status, {
    String? fromUserId,
    bool persistable = true,
  }) {
    if (fromUserId == null) {
      // A wholesale receipt (no per-user bookkeeping) must not regress a
      // message that already reached a higher state via an out-of-order
      // frame (a late `delivered` after a `read`).
      if (!_setReceipt(messageId, status, persistable: persistable)) return;
      _propagateAggregated(messageId, status, persistable: persistable);
      notifyListeners();
      return;
    }

    _recordReceiptFor(messageId, status, fromUserId, persistable: persistable);

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
          _recordReceiptFor(m.id, status, fromUserId, persistable: persistable);
        }
      }
    }
    notifyListeners();
  }

  void _recordReceiptFor(
    String messageId,
    ReceiptStatus status,
    String fromUserId, {
    bool persistable = true,
  }) {
    // Keep the per-user breakdown clean too, not just the aggregate: an ack
    // recorded under a temporary id outlives the id itself, and would be
    // re-derived into a receipt by the next [_recomputeAllReceipts] — after
    // reconciliation dropped the pending mark that [_setReceipt] relies on.
    if (_isUnsent(messageId)) return;
    if (status == ReceiptStatus.delivered) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
    } else if (status == ReceiptStatus.read) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
      (_readBy[messageId] ??= <String>{}).add(fromUserId);
    }
    _setReceipt(
      messageId,
      _aggregateStatus(messageId),
      persistable: persistable,
    );
  }

  /// Records the server-assigned [seq] of [messageId], learned from a
  /// `message_acked` event. Seqs let [applyDeliveryCursor] decide
  /// coverage numerically when the cursor message itself is not loaded.
  void recordMessageSeq(String messageId, int seq) {
    _seqByMessageId[messageId] = seq;
  }

  /// Applies [userId]'s delivered cursor (`message_delivered` event):
  /// every message at-or-before [messageId] in conversation order — any
  /// author — is now delivered to them, and the aggregated statuses are
  /// recomputed.
  ///
  /// Cursors are max-registers: when [seq] is known and not newer than
  /// the last applied cursor for [userId], the call is a silent no-op,
  /// so duplicated or reordered events are harmless. When the cursor
  /// message is not loaded yet, the cursor is stashed and re-applied as
  /// soon as [setMessages]/[addMessages] bring it in.
  void applyDeliveryCursor({
    required String userId,
    required String messageId,
    int? seq,
  }) {
    final current = _deliveredCursors[userId];
    final currentSeq = current?.seq;
    if (currentSeq != null && seq != null && seq <= currentSeq) return;
    _deliveredCursors[userId] = (messageId: messageId, seq: seq);
    if (_applyDeliveredCursorFor(userId)) notifyListeners();
  }

  /// Marks every message covered by [userId]'s stashed cursor as
  /// delivered by them. Coverage: numeric (`seq`) when both the cursor
  /// and the message have a known seq; conversation order otherwise.
  /// Returns `true` when at least one visible status changed.
  bool _applyDeliveredCursorFor(String userId) {
    final cursor = _deliveredCursors[userId];
    if (cursor == null) return false;
    final cursorIndex = _indexById[cursor.messageId];
    final cursorSeq = cursor.seq;
    if (cursorIndex == null && cursorSeq == null) return false;
    var changed = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      // Index-based coverage is blind to what a row actually is: an
      // optimistic row sits in conversation order like any other and would
      // fall inside a cursor that can only have been computed from server
      // history.
      if (_isUnsent(m.id)) continue;
      final msgSeq = _seqByMessageId[m.id];
      final covered = (cursorSeq != null && msgSeq != null)
          ? msgSeq <= cursorSeq
          : (cursorIndex != null && i <= cursorIndex);
      if (!covered) continue;
      final delivered = _deliveredBy[m.id] ??= <String>{};
      if (!delivered.add(userId)) continue;
      if (_setReceipt(m.id, _aggregateStatus(m.id))) changed = true;
    }
    return changed;
  }

  void _reapplyDeliveredCursors() {
    for (final userId in _deliveredCursors.keys) {
      _applyDeliveredCursorFor(userId);
    }
  }

  /// The receipt currently known for [messageId] — the aggregated value if
  /// one was recorded, else the message's own server-provided [receipt].
  /// `null` when the message isn't in the controller and no receipt landed.
  ReceiptStatus? _receiptFor(String messageId) {
    final recorded = _receiptStatuses[messageId];
    if (recorded != null) return recorded;
    final index = _indexById[messageId];
    return index != null ? _messages[index].receipt : null;
  }

  /// The single writer of [_receiptStatuses]. Receipt state is monotonic:
  /// [status] only lands when it strictly outranks what the bubble already
  /// shows ([_receiptFor], which accounts for the message's own baseline
  /// receipt). A `null` [status] means "not derivable right now" and leaves
  /// the current state untouched. Returns `true` when the visible status
  /// changed.
  ///
  /// The guard lives here, not at the call sites, because every source of a
  /// lower value is legitimate on its own terms — an out-of-order frame, a
  /// re-aggregation under a roster that shrank, a group/1:1 reclassification
  /// — and none of them may turn a ✓✓ back into a ✓.
  ///
  /// It is also where unsent rows are turned away, for the same reason:
  /// every fan-out that reaches a row it never got an event for — the
  /// high-water-mark walk in [updateReceipt], [_propagateAggregated],
  /// [_applyDeliveredCursorFor] — sweeps the whole list by timestamp or
  /// index and would otherwise sweep up the user's own failed sends along
  /// with the real ones. A pending or failed row carries no receipt at
  /// all: it is stamped by nothing, queued for persistence by nothing, and
  /// so never reaches the cache as message history claiming to have been
  /// delivered and read.
  bool _setReceipt(
    String messageId,
    ReceiptStatus? status, {
    bool persistable = true,
  }) {
    if (status == null) return false;
    if (_isUnsent(messageId)) return false;
    if (_rankReceipt(status) <= _rankReceipt(_receiptFor(messageId))) {
      return false;
    }
    _receiptStatuses[messageId] = status;
    // Recorded against the row, not against the call that is running: the
    // queue is shared and drained by whoever gets there first, so the only
    // way to hold a value back from all of them is for the controller to
    // know the row carries one.
    if (!persistable) _heldBackReceipts.add(messageId);
    _stampReceiptOnMessage(messageId, status);
    return true;
  }

  /// Mirrors an advanced aggregate onto the message object itself and
  /// queues the id for [drainReceiptUpdates]. Receipts reach the SDK as
  /// events, never as message rows, so without this pass nothing the cache
  /// ever writes would carry them and every ✓✓ would die with the process.
  void _stampReceiptOnMessage(String messageId, ReceiptStatus status) {
    final index = _indexById[messageId];
    if (index == null) return;
    final msg = _messages[index];
    if (msg.receipt == status) return;
    _messages[index] = msg.copyWith(receipt: status);
    _receiptDirty.add(messageId);
  }

  /// Stamps [incoming] with the furthest-along receipt known for the slot
  /// it is about to occupy: its own, the one [replaced] carried, and the
  /// aggregates recorded under either id. This is [_setReceipt]'s
  /// monotonic rule applied to the message object rather than to the
  /// aggregate map, and it is what stops a bubble already showing ✓✓ from
  /// falling back to ✓ when a payload without a receipt — every REST row —
  /// takes its place.
  ChatMessage _mergeReceiptInto(ChatMessage incoming, [ChatMessage? replaced]) {
    final known = ReceiptStatus.highest(
      ReceiptStatus.highest(incoming.receipt, _receiptStatuses[incoming.id]),
      replaced == null
          ? null
          : ReceiptStatus.highest(
              replaced.receipt,
              _receiptStatuses[replaced.id],
            ),
    );
    if (known == incoming.receipt) return incoming;
    // The hold-back is a property of the value, so it survives the row
    // being re-keyed along with the value itself.
    if (replaced != null && _heldBackReceipts.contains(replaced.id)) {
      _heldBackReceipts.add(incoming.id);
    }
    _setReceipt(incoming.id, known);
    // Queued here rather than left to [_setReceipt], which declines an
    // equal rank — the shape of a receipt that landed before the row it
    // belongs to, recorded in [_receiptStatuses] and stamped on nothing.
    // This merge is where such a row finally gets the value, and the wire
    // row it arrived as carries none, so without this the cache keeps the
    // receipt-less one. What the replaced row already carried is excluded:
    // that value came off the cache to begin with.
    if (!_isUnsent(incoming.id) &&
        _rankReceipt(known) > _rankReceipt(replaced?.receipt)) {
      _receiptDirty.add(incoming.id);
    }
    return incoming.copyWith(receipt: known);
  }

  /// The messages whose receipt advanced since the last call, ready to be
  /// written back to the cache — [receiptStatuses] lives only in memory,
  /// `ChatMessage.receipt` is what survives a cold start. Draining clears
  /// the queue: the caller owns the write from that point on.
  ///
  /// Consumers should NOT call this directly — the adapter drains it after
  /// every receipt-bearing event and after the room-open rehydration.
  ///
  /// This is the only way out of the controller, which is why the
  /// hold-back is applied here rather than by the caller that asked for
  /// it: the two consumers share one queue and either can drain the
  /// other's rows, so a rule enforced on one side of it holds for neither.
  List<ChatMessage> drainReceiptUpdates() {
    if (_receiptDirty.isEmpty) return const <ChatMessage>[];
    final updated = <ChatMessage>[];
    for (final id in _receiptDirty) {
      if (_heldBackReceipts.contains(id)) continue;
      final index = _indexById[id];
      if (index != null) updated.add(_messages[index]);
    }
    _receiptDirty.clear();
    return updated;
  }

  /// A whole-controller reset escaping the monotonicity of [_setReceipt]:
  /// a room reloaded from scratch ([clearMessages]) must not carry acks over
  /// to whatever lands next under the same ids. [_revokeReceiptFor] is the
  /// same escape narrowed to a single row.
  void _clearReceipts() {
    _receiptStatuses.clear();
    _receiptDirty.clear();
    _heldBackReceipts.clear();
    _readBy.clear();
    _deliveredBy.clear();
    _seqByMessageId.clear();
    _deliveredCursors.clear();
  }

  /// The aggregated status for [messageId] derived from the per-user
  /// breakdown, or `null` when it is not derivable yet — see [_setReceipt],
  /// the only consumer, which treats `null` as "leave it alone".
  ReceiptStatus? _aggregateStatus(String messageId) {
    final otherUserIds = _otherUsers.map((u) => u.id).toSet();
    final totalOthers = otherUserIds.length;
    // Treat the chat as 1:1 only when we KNOW it isn't a group. When the
    // group flag hasn't been set we fall back to the member count, but a
    // known group is never collapsed to 1:1 — otherwise a not-yet-hydrated
    // group (0–1 known members) would mark messages "read by all" the instant
    // a single peer read, and stay stuck there permanently.
    final treatAsOneToOne = _isGroup == null ? totalOthers <= 1 : !_isGroup!;
    if (treatAsOneToOne) {
      // 1:1: any read => read; any delivered => delivered. Derived from the
      // per-user acks alone, so the roster being empty can't skew it.
      final readers = _readBy[messageId];
      if (readers != null && readers.isNotEmpty) return ReceiptStatus.read;
      final delivered = _deliveredBy[messageId];
      if (delivered != null && delivered.isNotEmpty) {
        return ReceiptStatus.delivered;
      }
      return ReceiptStatus.sent;
    }
    // Group: only mark as read once *every* other member has read, which
    // needs the roster as the divisor. An empty roster on a group is member
    // hydration not having landed — a group is never a room with nobody in
    // it — so the aggregate is UNKNOWN, not `sent`: reporting `sent` here
    // would downgrade every already-read message on each re-entry into the
    // app, when the controller is rebuilt ahead of its member list.
    if (totalOthers == 0) return null;
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
  void _propagateAggregated(
    String messageId,
    ReceiptStatus status, {
    bool persistable = true,
  }) {
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
      _setReceipt(m.id, status, persistable: persistable);
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

  static int _rankReceipt(ReceiptStatus? status) => status?.rank ?? 0;

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

  /// Marks the initial-load phase as settled. Called once by
  /// [ChatMessagesController.load] after both the cache and network phases
  /// have resolved, regardless of outcome — a failed load still stops
  /// "loading" so the view can fall back to the empty state / error banner
  /// instead of spinning forever.
  void setLoadingInitial(bool loading) {
    if (_isLoadingInitial == loading) return;
    _isLoadingInitial = loading;
    notifyListeners();
  }

  /// Records the load-more pagination state. [cursor] is the opaque
  /// older-history cursor ([ChatPaginatedResponse.prevCursor]) anchored on the
  /// oldest message of the page just loaded; [hasMore] reflects whether older
  /// history remains.
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
    _indexByClientMessageId.clear();
    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      _indexById[msg.id] = i;
      final cmid = msg.clientMessageId;
      if (cmid != null) _indexByClientMessageId[cmid] = i;
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
