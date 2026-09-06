part of '../chat_ui_adapter.dart';

/// The read-receipt machinery behind [ChatMessagesController.loadReceipts]
/// and the receipt rehydration a page load performs: the cached rows for a
/// room, the cursor timestamps they resolve to, the pass that stamps a
/// freshly loaded window with them and the write-back that persists it.
///
/// The public entry points stay on the controller; only the machinery they
/// drive lives here, as a `part` of the adapter library so it reads and
/// writes the same private state it did when it sat in the controller body.
extension _MessageReceipts on ChatMessagesController {
  /// Applies room-level receipts (read + delivered cursors) to
  /// messages already in the controller — used post-login to restore
  /// ✓✓ marks that the WS event stream can no longer replay.
  /// Fire-and-forget: any failure simply leaves bubbles as ✓ (single
  /// tick), same as before the rehydration was added.
  ///
  /// Read coverage always resolves `lastReadMessageId` to a position in
  /// conversation order: the cursor's own index when it is inside the
  /// loaded window, its timestamp read back from the local cache when it
  /// is not. A cursor id that resolves to neither marks NOTHING.
  ///
  /// It must not fall back to `lastReadAt` there, however tempting: that
  /// field is the instant the SERVER recorded the confirmation, not the
  /// time of the message that was read, and a cursor only paginates out
  /// of the window when the peer's read position is old — which is
  /// exactly when the recent messages are genuinely unread and yet
  /// timestamped before that confirmation. Marking them would tell the
  /// sender the peer read messages they never opened, and receipt state
  /// is monotonic, so the genuine `delivered` that follows could never
  /// walk it back.
  ///
  /// `lastReadAt` is used for one row shape only: no cursor id at all,
  /// which the backend writes exclusively for whole-room reads
  /// (`chat_engine_read_receipts:advance_room_cursors/3` stores
  /// `lastReadMessageId = null` alongside a seq snapshot of the whole
  /// conversation). There the cursor's extent *is* "every message in the
  /// room at that instant", so the confirmation time reconstructs it
  /// rather than standing in for a message. Those marks still show up in
  /// the UI but are applied `persistable: false`, which keeps them out of
  /// every write-back — this one and the event router's alike.
  ///
  /// Delivered coverage applies the `lastDeliveredMessageId` cursor via
  /// [ChatController.applyDeliveryCursor].
  ///
  /// Also propagates the resulting aggregate status of the room's
  /// LAST outgoing message into the room-list row so the ticks in the
  /// chat list re-hydrate in lockstep with the bubbles.
  Future<void> _rehydrateOutgoingReceipts(
    String roomId,
    ChatController controller,
  ) async {
    final result = await _a.client.messages.getRoomReceipts(roomId);
    if (result.isFailure || _a._disposed) return;
    final receipts = result.dataOrThrow.items;
    if (receipts.isEmpty) return;
    final cachedTimestamps = await _cursorTimestamps(
      roomId,
      receipts,
      controller.messages,
      includeOwnCursor: controller.isSelfConversation,
    );
    if (_a._disposed) return;
    _applyRoomReceipts(roomId, controller, receipts, cachedTimestamps);
  }

  /// Reads the room's receipt cursors straight off the local datasource,
  /// bypassing `messages.getRoomReceipts` — that call is pinned to
  /// `networkFirst` on purpose (a peer can read while this app is not
  /// running, and nothing local invalidates the stored copy), and the pin
  /// stays. This is the *other* half: what the last session already knew,
  /// available in one Hive read instead of two round trips, so the first
  /// painted frame can carry the ticks the previous one ended with. The
  /// network pass still runs afterwards and can only advance them —
  /// [ChatController] refuses a receipt that ranks below the one a row
  /// already holds, so an outdated cursor cannot walk a tick backwards.
  ///
  /// Empty when the adapter was built without a `cache:`, which leaves the
  /// behaviour exactly as it was before this path existed.
  Future<List<ReadReceipt>> _cachedRoomReceipts(String roomId) async {
    final cache = _a._cache;
    if (cache == null) return const <ReadReceipt>[];
    final stored = await cache.getReceipts(roomId);
    return stored.dataOrNull ?? const <ReadReceipt>[];
  }

  /// Cached id → timestamp map, read only when some read cursor in
  /// [receipts] points outside [window] and therefore has to be placed in
  /// conversation order by the cursor message's own time. Empty otherwise,
  /// which is the common case and costs nothing.
  ///
  /// Resolved up front rather than lazily inside the apply loop so that
  /// loop can be synchronous: an `await` in the middle of it would split
  /// the turn, and a frame painted in that gap is the flicker this exists
  /// to remove.
  Future<Map<String, DateTime>> _cursorTimestamps(
    String roomId,
    List<ReadReceipt> receipts,
    List<ChatMessage> window, {
    bool includeOwnCursor = false,
  }) async {
    final currentUserId = _a.currentUser.id;
    final needed = receipts.any((r) {
      if (r.userId == currentUserId && !includeOwnCursor) return false;
      final id = r.lastReadMessageId;
      return id != null && !window.any((m) => m.id == id);
    });
    if (!needed) return const <String, DateTime>{};
    return _cachedMessageTimestamps(roomId);
  }

  /// Applies [receipts] onto [controller]. Synchronous by contract: every
  /// caller resolves what it needs first, so the ticks a batch implies land
  /// in the same turn as the messages they belong to.
  void _applyRoomReceipts(
    String roomId,
    ChatController controller,
    List<ReadReceipt> receipts,
    Map<String, DateTime> cachedTimestamps,
  ) {
    final currentUserId = _a.currentUser.id;
    // The user's own cursor says what THIS user read, not what an audience
    // received, so it is dropped — except in a room with nobody else in it,
    // where the user IS the audience and their cursor is the only receipt
    // those messages can ever get. Same exemption the live receipt frames
    // carry, so reopening the room re-derives the mark the session that
    // received the echo deliberately kept out of the cache.
    final ownCursorCounts = controller.isSelfConversation;
    for (final r in receipts) {
      if (r.userId == currentUserId && !ownCursorCounts) continue;
      final lastDeliveredId = r.lastDeliveredMessageId;
      if (lastDeliveredId != null) {
        controller.applyDeliveryCursor(
          userId: r.userId,
          messageId: lastDeliveredId,
        );
      }
      final lastReadId = r.lastReadMessageId;
      final lastReadAt = r.lastReadAt;
      final int? cutoffIndex;
      final DateTime? cutoffTime;
      // Tie-breaker for messages sharing the cutoff's exact timestamp, so
      // the timestamp path covers the same set the index path would: the
      // controller sorts by (timestamp, id).
      final String? cutoffId;
      if (lastReadId != null) {
        final index = controller.messages.indexWhere((m) => m.id == lastReadId);
        if (index >= 0) {
          cutoffIndex = index;
          cutoffTime = null;
          cutoffId = null;
        } else {
          final resolved = cachedTimestamps[lastReadId];
          if (resolved == null) continue;
          cutoffIndex = null;
          cutoffTime = resolved;
          cutoffId = lastReadId;
        }
      } else if (lastReadAt != null) {
        cutoffIndex = null;
        cutoffTime = lastReadAt;
        cutoffId = null;
      } else {
        continue;
      }
      final traced = cutoffIndex != null || cutoffId != null;
      final messages = controller.messages;
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg.from != currentUserId) continue;
        if (msg.receipt == ReceiptStatus.read) continue;
        // An optimistic row still carries a temporary id and a local
        // clock's timestamp — no peer cursor can refer to it, and its
        // timestamp is not comparable with a server-side one.
        if (controller.isPending(msg.id) || controller.isFailed(msg.id)) {
          continue;
        }
        final bool covered;
        if (cutoffIndex != null) {
          covered = i <= cutoffIndex;
        } else {
          final order = msg.timestamp.compareTo(cutoffTime!);
          covered =
              order < 0 ||
              (order == 0 &&
                  (cutoffId == null || msg.id.compareTo(cutoffId) <= 0));
        }
        if (!covered) continue;
        controller.updateReceipt(
          msg.id,
          ReceiptStatus.read,
          fromUserId: r.userId,
          persistable: traced,
        );
      }
    }
    // Persist what the rehydration recovered. Without this the same
    // round trip repeats on every open: the receipts endpoint is the
    // only place these marks exist, so the cached rows have to take
    // them over for the NEXT cold start to render ✓✓ before the
    // network answers.
    //
    // Everything derived from a whole-room confirmation time is excluded:
    // a cached receipt is permanent (the merge on read keeps the highest
    // value ever stored), so only marks that trace to a cursor — the ones
    // the next rehydration would derive again from the same evidence —
    // earn that. The rest live for this session and are re-derived, or
    // corrected, on the next open. The exclusion is the controller's, not
    // this drain's: the queue is shared with the event router, which drains
    // it on every receipt frame, so a rule applied by one caller of it
    // would hold for neither.
    final recovered = controller.drainReceiptUpdates();
    if (recovered.isNotEmpty) {
      unawaited(_persistReceiptRows(roomId, recovered));
    }

    // Sync the room-list tile so the tick under the room name matches
    // the bubble status. Walks newest-to-oldest looking for the most
    // recent outgoing message in the controller; pushes its aggregated
    // status (now reflecting the rehydration above) into the row only
    // when it's the one currently shown as the preview — otherwise the
    // tile is already rendering a different message and we'd overwrite
    // stale state.
    for (final msg in controller.messages.reversed) {
      if (msg.from != currentUserId) continue;
      final status = controller.receiptStatuses[msg.id];
      if (status == null) return;
      _a._roomListMutator.updateRoomListReceipt(roomId, msg.id, status);
      return;
    }
  }

  Future<void> _persistReceiptRows(
    String roomId,
    List<ChatMessage> rows,
  ) async {
    final cache = _a._cache;
    if (cache == null) return;
    await cache.saveMessages(roomId, rows);
  }

  /// Timestamps of every message [roomId] holds in the local cache, keyed
  /// by id. Lets a read cursor pointing outside the loaded window still be
  /// placed in conversation order — by the cursor message's OWN time, the
  /// only thing that makes the resulting mark evidence of a read. Empty
  /// when the adapter was built without a `cache:` (the consumer's own
  /// datasource is not reachable from here), which leaves such a cursor
  /// unresolvable and marks nothing.
  Future<Map<String, DateTime>> _cachedMessageTimestamps(String roomId) async {
    final cache = _a._cache;
    if (cache == null) return const <String, DateTime>{};
    final rows = (await cache.getMessages(roomId)).dataOrNull;
    if (rows == null) return const <String, DateTime>{};
    return {for (final m in rows) m.id: m.timestamp};
  }
}
