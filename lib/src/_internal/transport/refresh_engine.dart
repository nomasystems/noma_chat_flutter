import '../../config/polling_config.dart';
import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../../models/unread_room.dart';
import '../../models/user_rooms.dart';

/// Diff/emit core shared by [PollingTransport] (timer-driven) and
/// [ManualTransport] (caller-driven). Owns no I/O of its own — the
/// caller supplies thunks for `rooms.getUserRooms` and `messages.list`
/// and a `void Function(ChatEvent)` to dispatch the synthetic events
/// back onto the transport's stream.
///
/// Limitations (inherent to REST polling without a server-pushed diff
/// feed). These are the price of `RealtimeMode.polling` / `.manual`; the
/// default `auto` (WS→SSE) gets all of the below live via push:
/// * Typing / presence / DM-activity are **not** emitted — they're
///   transient events with no REST equivalent.
/// * **Reactions and message edits on EXISTING messages are not
///   propagated live.** The engine only synthesizes `NewMessageEvent`s
///   for messages newer than its per-room cursor and diffs room-list
///   fields (last message, unread, receipt, avatar, name); a reaction or
///   an in-place edit on an older message changes neither, so it isn't
///   detected. Such changes surface only when the chat is freshly
///   (re)loaded (`messages.list` returns the current row). WS/SSE deliver
///   `reaction_added` / `message_updated` instantly. This is an accepted
///   trade-off of the degraded transports, not a bug.
/// * Hard-deleted messages are invisible until something else
///   invalidates the local cache; soft-deletes (`isDeleted: true`)
///   surface as a `NewMessageEvent` carrying the deleted payload — the
///   adapter renders the "deleted" placeholder.
class RefreshEngine {
  final Future<ChatResult<UserRooms>> Function({String type}) _getUserRooms;
  final Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> Function(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  })
  _listMessages;
  final void Function(ChatEvent) _emit;
  final PollingConfig _config;
  final void Function(String level, String message)? _logger;

  final Map<String, _RoomSnapshot> _snapshots = {};

  /// Per-room opaque forward cursor (the `next` token from the previous poll).
  /// Realtime catch-up resumes from this position with
  /// `direction: ChatCursorDirection.newer`. Absent until the first page for a
  /// room arrives; until then the room is polled with no cursor (most recent
  /// page).
  final Map<String, String> _nextCursor = {};

  /// Set once on construction so the FIRST [tick] after a (re)build clears any
  /// pagination cursors that may have been carried over from a previous build.
  /// After that first tick the engine resumes incremental polling normally.
  bool _staleStatePurgePending = true;

  final Set<String> _openRoomIds = {};

  /// Re-entrancy guard. A tick performs several awaited round-trips
  /// (`getUserRooms`, then per-room `messages.list`); without this a fast
  /// poll interval — or a manual `refreshRoom` landing mid-tick — could start
  /// a second concurrent tick that interleaves `_nextCursor`/`_snapshots`
  /// mutations and emits duplicate `newMessage` events. Mirrors
  /// `OfflineQueue._drainWith`'s `_processing` latch.
  bool _ticking = false;

  RefreshEngine({
    required Future<ChatResult<UserRooms>> Function({String type}) getUserRooms,
    required Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> Function(
      String roomId, {
      ChatCursorPaginationParams? pagination,
    })
    listMessages,
    required void Function(ChatEvent) emit,
    required PollingConfig config,
    void Function(String level, String message)? logger,
  }) : _getUserRooms = getUserRooms,
       _listMessages = listMessages,
       _emit = emit,
       _config = config,
       _logger = logger;

  /// Mark a room as "currently visible" so [tick] additionally polls
  /// it even when no diff was detected. Called by the adapter when a
  /// `ChatController` becomes active.
  void markRoomOpen(String roomId) => _openRoomIds.add(roomId);

  /// Mark a room as no longer visible. Called when the controller is
  /// disposed.
  void markRoomClosed(String roomId) => _openRoomIds.remove(roomId);

  /// Run one full tick: diff the room list, then pull new messages
  /// for any room that changed (plus the open rooms, capped by
  /// [PollingConfig.maxRoomsPerTick]).
  ///
  /// When [singleRoomId] is provided, skip the room-list diff and pull
  /// messages for that room only. Used by `chat.refreshRoom(roomId)`
  /// in manual mode.
  Future<void> tick({String? singleRoomId}) async {
    // Re-entrancy guard: skip if a tick is already in flight so concurrent
    // calls can't interleave cursor/snapshot mutations or double-emit events.
    if (_ticking) return;
    _ticking = true;
    try {
      await _tick(singleRoomId: singleRoomId);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick({String? singleRoomId}) async {
    if (_staleStatePurgePending) {
      // First tick of this engine instance: drop any forward cursors that
      // might be stale relative to the current backend state. We keep
      // `_snapshots`/`_openRoomIds` (they only drive room-list diffing) but
      // reset the message-position state so the engine resumes cleanly from
      // the most recent page.
      _nextCursor.clear();
      _staleStatePurgePending = false;
    }
    if (singleRoomId != null) {
      await _pollRoomMessages(singleRoomId);
      return;
    }
    // The room-list diff ALWAYS pulls `type=all`, never `unread`.
    // Rationale: a read-receipt change on MY outgoing message (peer
    // opened the chat → ✓✓ blue) lands on a room whose unread count
    // is 0 for me. With `type=unread` that room never comes back in
    // the poll, so the tick stayed stuck on ✓ forever (reported
    // 2026-05-28: bob/charlie's chat-list tick didn't update after
    // alice read). `pollUnreadOnly` now only governs whether we go
    // on to poll *messages* for unchanged rooms — the room-list diff
    // (which drives receipt/avatar/name updates) needs the full set.
    final roomsResult = await _getUserRooms(type: 'all');
    if (roomsResult.isFailure) {
      _logger?.call(
        'warn',
        'RefreshEngine.tick: getUserRooms failed: ${roomsResult.failureOrNull}',
      );
      return;
    }
    final roomsNow = roomsResult.dataOrThrow.rooms;
    final idsNow = roomsNow.map((r) => r.roomId).toSet();
    final idsPrev = _snapshots.keys.toSet();

    // Rooms that disappeared from the list.
    for (final goneId in idsPrev.difference(idsNow)) {
      _snapshots.remove(goneId);
      _emit(ChatEvent.roomDeleted(roomId: goneId));
    }

    // New / updated rooms.
    final toPoll = <String>{..._openRoomIds.where(idsNow.contains)};
    // Rooms whose unread count changed → we re-assert the backend's
    // authoritative count AFTER the message poll below (see end of tick),
    // so it overrides any local increment a synthesized `newMessage` made.
    // Without this the chat-list badge drifts: it was counted locally and
    // never reconciled with the server, so a peer's read (count drops) or a
    // re-delivered message (count inflates) left a stale/duplicated badge.
    final unreadSync = <String, int>{};
    for (final room in roomsNow) {
      final prev = _snapshots[room.roomId];
      if (prev == null) {
        _emit(ChatEvent.roomCreated(roomId: room.roomId));
        toPoll.add(room.roomId);
      } else if (_hasChanged(prev, room)) {
        toPoll.add(room.roomId);
        // Emit roomUpdated so the adapter invalidates the room
        // detail cache and re-fetches `rooms.get(roomId)` — that's
        // the only path that picks up avatar / name / muted / pinned
        // / receipt changes. Without this the polling transport only
        // surfaced `newMessage`, so a change of avatar or a "read by
        // peer" tick update was invisible until the next cold
        // reload. Cheap when nothing changed (compare-only).
        _emit(ChatEvent.roomUpdated(roomId: room.roomId));
        final receiptChanged =
            prev.lastMessageReceipt != room.lastMessageReceipt &&
            room.lastMessageReceipt != null &&
            room.lastMessageId != null;
        final receiptMine = room.lastMessageUserId == _currentUserIdOrNull();
        if (receiptChanged && receiptMine) {
          // My outgoing message got a receipt change (✓ → ✓✓ → ✓✓ blue)
          // — emit explicit ReceiptUpdated so the room tile and the open
          // chat bubble repaint without waiting for a manual refresh.
          _emit(
            ChatEvent.receiptUpdated(
              roomId: room.roomId,
              messageId: room.lastMessageId!,
              status: room.lastMessageReceipt!,
              fromUserId: null,
            ),
          );
        }
        if (prev.unreadCount != room.unreadMessages) {
          // You can't have unread on your OWN last message — sending
          // implies having read everything before it. The backend can
          // briefly report a non-zero unread for the sender's freshly-sent
          // message (seen on polling: charlie DMs alice and his own message
          // shows as "1 unread"). Force 0 when we're the last sender so the
          // chat-list badge never counts our own message.
          final me = _currentUserIdOrNull();
          unreadSync[room.roomId] = (me != null && room.lastMessageUserId == me)
              ? 0
              : room.unreadMessages;
        }
      }
      _snapshots[room.roomId] = _RoomSnapshot.from(room);
    }

    final limited = toPoll.toList().take(_config.maxRoomsPerTick);
    for (final roomId in limited) {
      await _pollRoomMessages(roomId);
    }

    // Authoritative unread reconciliation — emitted AFTER the message poll so
    // it has the last word over any local increment from a synthesized
    // `newMessage`. `updateRoomUnread` SETS (not increments) the badge.
    unreadSync.forEach((roomId, count) {
      _emit(ChatEvent.unreadUpdated(roomId: roomId, count: count));
    });
  }

  /// Optional accessor for the current user id — used to gate the
  /// `receiptUpdated` emit on lastMessage that we own. Settable by the
  /// transport wiring; falls back to `null` when unset (no receipt
  /// emission, only roomUpdated).
  String? Function()? _currentUserIdFn;
  void setCurrentUserIdSource(String? Function() fn) {
    _currentUserIdFn = fn;
  }

  String? _currentUserIdOrNull() => _currentUserIdFn?.call();

  bool _hasChanged(_RoomSnapshot prev, UnreadRoom curr) =>
      prev.lastMessageId != curr.lastMessageId ||
      prev.lastMessageTime != curr.lastMessageTime ||
      prev.unreadCount != curr.unreadMessages ||
      prev.lastMessageReceipt != curr.lastMessageReceipt ||
      prev.avatarUrl != curr.avatarUrl ||
      prev.name != curr.name;

  Future<void> _pollRoomMessages(String roomId) async {
    final storedCursor = _nextCursor[roomId];

    // Realtime catch-up: resume from the stored forward cursor travelling
    // `newer`. The seq-based opaque cursor encodes the precise position, so
    // identical-timestamp messages can't be skipped or replayed and no id
    // dedup is needed. Until a room has a cursor (first poll) we fetch the
    // most recent page with no cursor and adopt the `next` it returns.
    final pagination = storedCursor != null
        ? ChatCursorPaginationParams(
            cursor: storedCursor,
            direction: ChatCursorDirection.newer,
          )
        : null;

    final result = await _listMessages(roomId, pagination: pagination);
    if (result.isFailure) {
      _logger?.call(
        'warn',
        'RefreshEngine.poll: messages.list($roomId) failed: '
            '${result.failureOrNull}',
      );
      return;
    }
    final page = result.dataOrThrow;

    for (final msg in page.items) {
      _emit(ChatEvent.newMessage(roomId: roomId, message: msg));
    }

    // Advance the forward cursor only when the backend hands us a fresh one;
    // otherwise keep the current cursor so the next poll retries from the same
    // position (an empty page yields no new cursor).
    final nextCursor = page.nextCursor;
    if (nextCursor != null) _nextCursor[roomId] = nextCursor;
  }

  /// Reset all tracked state (used by the transport on reconnect to guarantee
  /// no stale `_nextCursor` survives a network gap — a cursor frozen before the
  /// gap would resume from an outdated seq position and miss messages
  /// delivered while disconnected).
  void reset() {
    _snapshots.clear();
    _nextCursor.clear();
    // Don't clear `_openRoomIds` — the adapter still has live
    // controllers; we want to keep polling them after reconnect.
  }
}

class _RoomSnapshot {
  final DateTime? lastMessageTime;
  final String? lastMessageId;
  final int unreadCount;
  final ReceiptStatus? lastMessageReceipt;
  final String? avatarUrl;
  final String? name;

  _RoomSnapshot.from(UnreadRoom r)
    : lastMessageTime = r.lastMessageTime,
      lastMessageId = r.lastMessageId,
      unreadCount = r.unreadMessages,
      lastMessageReceipt = r.lastMessageReceipt,
      avatarUrl = r.avatarUrl,
      name = r.name;
}
