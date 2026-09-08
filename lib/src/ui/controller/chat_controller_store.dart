part of 'chat_controller.dart';

/// How [ChatController] keeps its message list addressable: the lookups
/// by server and client id, the rule that decides whether an incoming row
/// replaces the one already held, the id reconciliation that follows a
/// confirmed send, the index rebuild and the trim to [ChatController.maxMessages].
extension _ChatControllerStore on ChatController {
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

  /// `true` while [messageId] names an optimistic row whose send has not
  /// been confirmed — still in flight ([markPending]) or given up on
  /// ([markFailed]).
  ///
  /// Such a row exists on this device only: the server never accepted it,
  /// so nobody can have received or read it, and its temporary id is not
  /// one any peer cursor can legitimately refer to. Receipts must
  /// therefore stop at its door — see [_setReceipt].
  bool _isUnsent(String messageId) => _pendingMessages.containsKey(messageId);

  /// `true` while [messageId] names a row whose delivery state is frozen at
  /// [ReceiptStatus.sent]: the server accepted nothing, or accepted and
  /// dropped it, because the recipient blocks the sender. No cursor, no
  /// fan-out and no per-user ack may advance such a row — the ✓✓ it would
  /// paint describes a delivery that never happened.
  bool _isPinnedSent(String messageId) {
    if (_pinnedSentIds.contains(messageId)) return true;
    final index = _indexById[messageId];
    return index != null && _messages[index].silentlyDropped;
  }

  void _trimMessages() {
    if (_messages.length > ChatController.maxMessages) {
      _messages.removeRange(0, _messages.length - ChatController.maxMessages);
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
}
