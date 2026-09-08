part of 'chat_controller.dart';

/// The read and delivery receipt bookkeeping [ChatController] keeps per
/// message: recording one, revoking it, replaying a delivery cursor over a
/// window, merging a receipt into the row it belongs to, and aggregating
/// the per-member states into the single status a bubble paints.
extension _ChatControllerReceipts on ChatController {
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

  void _recordReceiptFor(
    String messageId,
    ReceiptStatus status,
    String fromUserId, {
    bool persistable = true,
  }) {
    // A receipt attributed to the user themselves says nothing about the
    // audience: own reads are echoed back over the wire and would otherwise
    // land in [_readBy], where 1:1 aggregation reads "somebody read it".
    // Unless the user is the whole audience — see [isSelfConversation].
    final isOwnReceipt = fromUserId == currentUser.id;
    if (isOwnReceipt && !isSelfConversation) return;
    // Keep the per-user breakdown clean too, not just the aggregate: an ack
    // recorded under a temporary id outlives the id itself, and would be
    // re-derived into a receipt by the next [_recomputeAllReceipts] — after
    // reconciliation dropped the pending mark that [_setReceipt] relies on.
    if (_isUnsent(messageId) || _isPinnedSent(messageId)) return;
    _everAcknowledged.add(fromUserId);
    if (status == ReceiptStatus.delivered) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
    } else if (status == ReceiptStatus.read) {
      (_deliveredBy[messageId] ??= <String>{}).add(fromUserId);
      (_readBy[messageId] ??= <String>{}).add(fromUserId);
    }
    _setReceipt(
      messageId,
      _aggregateStatus(messageId),
      // An own receipt only counts because the room came back with nobody
      // else in it, and that is the one piece of evidence that can turn
      // out to have been a hydration miss. The cache merges receipts
      // upward and can never lower a stored one, so this mark stays out of
      // the write-back; the next room open re-derives it from the room's
      // own read cursor, which carries the same exemption.
      persistable: persistable && !isOwnReceipt,
    );
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
      if (_isUnsent(m.id) || _isPinnedSent(m.id)) continue;
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
    if (_isPinnedSent(messageId)) return false;
    if (ChatController._rankReceipt(status) <=
        ChatController._rankReceipt(_receiptFor(messageId))) {
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
        ChatController._rankReceipt(known) >
            ChatController._rankReceipt(replaced?.receipt)) {
      _receiptDirty.add(incoming.id);
    }
    return incoming.copyWith(receipt: known);
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
    _everAcknowledged.clear();
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
    // Blue stays strict: "read by everyone in the room" is a claim about
    // people, and narrowing its divisor would make the bubble say a member
    // read something they were never even shown.
    if (otherUserIds.every(readers.contains)) return ReceiptStatus.read;
    final delivered = _deliveredBy[messageId] ?? const <String>{};
    if (_deliveryQuorum(otherUserIds).every(delivered.contains)) {
      return ReceiptStatus.delivered;
    }
    // Some, but not all, members have ack'd — keep the bubble at sent
    // until at least delivered-by-all so the user sees the visual jump
    // exactly as WhatsApp renders it.
    return ReceiptStatus.sent;
  }

  /// The members a group message has to reach before its bubble leaves the
  /// single grey check. Under [GroupReceiptPolicy.allMembers] that is the
  /// whole roster; under [GroupReceiptPolicy.acknowledgingMembers] it is the
  /// roster narrowed to whoever has ever confirmed anything in this room —
  /// falling back to the whole roster while nobody has, so an untouched
  /// message is never reported as delivered to an empty audience.
  Set<String> _deliveryQuorum(Set<String> otherUserIds) {
    if (groupReceiptPolicy == GroupReceiptPolicy.allMembers) {
      return otherUserIds;
    }
    final acknowledging = otherUserIds.intersection(_everAcknowledged);
    return acknowledging.isEmpty ? otherUserIds : acknowledging;
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
      orElse: () => ChatController._absentReceiptReference,
    );
    if (identical(reference, ChatController._absentReceiptReference)) return;
    final referenceTs = reference.timestamp;
    final senderId = reference.from;
    for (final m in _messages) {
      if (m.id == messageId) continue;
      if (m.from != senderId) continue;
      if (m.timestamp.isAfter(referenceTs)) continue;
      _setReceipt(m.id, status, persistable: persistable);
    }
  }
}
