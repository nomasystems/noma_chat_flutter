import 'dart:async';

import 'package:flutter/widgets.dart';
import '../models/room_list_item.dart';

/// Manages the list of rooms displayed in [RoomListView].
///
/// Handles sorting (pinned first, then by last message time), text filtering,
/// and multi-selection state. Backed by [ChangeNotifier].
class RoomListController extends ChangeNotifier {
  RoomListController({List<RoomListItem> initialRooms = const []})
    : _rooms = List<RoomListItem>.from(initialRooms) {
    _sortRooms();
    _rebuildIndex();
  }

  final List<RoomListItem> _rooms;
  final Map<String, int> _indexById = {};
  final Set<String> _selectedIds = {};
  final Map<String, Map<String, Timer>> _typingTimers = {};

  /// Wall-clock time each row was last created/edited by a *local* action
  /// (draft materialization, a live `RoomCreatedEvent`, a rollback re-add),
  /// as opposed to landing from a server snapshot. Lets an authoritative
  /// [mergeRooms] spare a row the in-flight snapshot simply hadn't observed
  /// yet: a conversation created after the snapshot was captured must not be
  /// dropped just because that older snapshot omits it. The stamp is cleared
  /// as soon as an authoritative snapshot confirms the row (the server now
  /// vouches for it) or the row leaves the list.
  final Map<String, DateTime> _localTouchedAt = {};
  String _filter = '';
  bool _filterDirty = true;
  List<RoomListItem>? _cachedFilteredRooms;

  /// Monotonic counter behind [nextSeq]; [_lastAppliedSeq] is the highest
  /// sequence number any pass has actually reached the list with so far.
  int _seqCounter = 0;
  int _lastAppliedSeq = 0;

  /// Reserves the next monotonic sequence number for an in-flight network
  /// pass. Call once, right when the request is dispatched (the same
  /// moment a `snapshotAt` timestamp would be captured), and thread the
  /// returned value through to [mergeRooms] / [setRooms] /
  /// [allowsInferredPrune] so a pass that resolves out of order — an older
  /// fetch completing after a newer one already landed — is recognized as
  /// stale and denied its destructive (pruning) rights, while still being
  /// free to add/update rows non-destructively.
  int nextSeq() => ++_seqCounter;

  /// Single rule behind every DESTRUCTIVE removal that isn't a direct
  /// per-room confirmation (an explicit realtime event, a user action) but
  /// an absence/duplicate judgment drawn from a fetch pass — [mergeRooms]'s
  /// own authoritative-drop step and [allowsInferredPrune] (used by the DM
  /// dedupe's loser eviction) both go through this. A pass may prune only
  /// when [representsCompleteSet] is true (it covers the caller's complete
  /// room set, not a filtered/paginated view) AND [seq] is not older than
  /// the most recently applied pass — a reordered stale result must not
  /// undo what a newer pass already established.
  bool _acceptsPrune({required bool representsCompleteSet, int? seq}) {
    if (!representsCompleteSet) return false;
    if (seq != null && seq < _lastAppliedSeq) return false;
    return true;
  }

  void _recordAppliedSeq(int? seq) {
    if (seq != null && seq > _lastAppliedSeq) _lastAppliedSeq = seq;
  }

  /// Public counterpart of [_acceptsPrune] for callers outside this
  /// controller that need to gate their OWN destructive removal (e.g. the
  /// DM dedupe's loser eviction in `RoomEnricher._doResolveDmContact`)
  /// against the same recency/completeness rule [mergeRooms] enforces on
  /// itself.
  bool allowsInferredPrune({required bool representsCompleteSet, int? seq}) =>
      _acceptsPrune(representsCompleteSet: representsCompleteSet, seq: seq);

  /// Per-user "deleted" room ids — WhatsApp "Delete chat" parity. A
  /// deleted room is gone from BOTH the main list and the Archived
  /// section (unlike [RoomListItem.hidden], which only moves the room
  /// to Archived). It reappears empty only when a peer writes again,
  /// at which point the resurrection path clears it via [clearDeleted].
  /// The authoritative copy lives in the persistent cache
  /// (`getDeletedRoomIds`); this in-memory mirror lets the synchronous
  /// list getters exclude the row without a cache round-trip.
  final Set<String> _deletedRoomIds = {};

  /// Snapshot of the per-user deleted room ids.
  Set<String> get deletedRoomIds => Set.unmodifiable(_deletedRoomIds);

  List<RoomListItem> get rooms {
    if (_filterDirty || _cachedFilteredRooms == null) {
      final visible = _rooms.where((r) => !r.hidden && !_isDeleted(r.id));
      if (_filter.isEmpty) {
        _cachedFilteredRooms = List.unmodifiable(visible.toList());
      } else {
        final lower = _filter.toLowerCase();
        _cachedFilteredRooms = List.unmodifiable(
          visible.where(
            (r) =>
                (r.name?.toLowerCase().contains(lower) ?? false) ||
                (r.lastMessage?.toLowerCase().contains(lower) ?? false),
          ),
        );
      }
      _filterDirty = false;
    }
    return _cachedFilteredRooms!;
  }

  List<RoomListItem> get allRooms => List.unmodifiable(_rooms);

  /// Hidden ("archived") rooms, honouring the active text [filter] — the
  /// counterpart to [rooms] (which excludes hidden rooms). Drives the
  /// collapsible "Archived" section of [RoomListView]. Sorted like the
  /// main list (pinned first, then most-recent).
  List<RoomListItem> get archivedRooms {
    final archived = _rooms.where((r) => r.hidden && !_isDeleted(r.id));
    if (_filter.isEmpty) return List.unmodifiable(archived.toList());
    final lower = _filter.toLowerCase();
    return List.unmodifiable(
      archived.where(
        (r) =>
            (r.name?.toLowerCase().contains(lower) ?? false) ||
            (r.lastMessage?.toLowerCase().contains(lower) ?? false),
      ),
    );
  }

  /// `true` when at least one room is archived (ignoring the text filter).
  bool get hasArchivedRooms => _rooms.any((r) => r.hidden && !_isDeleted(r.id));

  /// How many conversations of the MAIN list carry unread messages.
  ///
  /// Counts exactly the rooms [rooms] is built from — `!hidden` and not in
  /// [deletedRoomIds] — with `unreadCount > 0`. Use it for the app/tab badge:
  /// every room it counts has a row the user can open (and thus clear) from
  /// the main list, and the count drops to zero the moment those rows are
  /// read, archived or deleted.
  ///
  /// Deliberately IGNORES the text [filter], unlike [rooms]: a badge that
  /// shrank while the user typed in the search box would be lying about the
  /// mailbox. [rooms] is a view; this is a total.
  ///
  /// [includeMuted] `false` (the default) skips rooms the user muted
  /// ([RoomListItem.muted]) — WhatsApp parity: a muted conversation must not
  /// drive an alerting badge. Pass `true` for an inbox-style "unread
  /// conversations" total where mute only silences notifications. Mute expiry
  /// is not evaluated locally: the flag is whatever the server last said, the
  /// same value the room tile paints its muted icon from.
  ///
  /// The archived half of the list is counted by [unreadArchivedRoomCount].
  /// The two are disjoint, and together they cover every non-deleted room, so
  /// `unreadRoomCount() + unreadArchivedRoomCount()` is the whole-account
  /// unread-conversation count under the same mute policy.
  int unreadRoomCount({bool includeMuted = false}) =>
      _countUnread(archived: false, includeMuted: includeMuted);

  /// How many ARCHIVED conversations carry unread messages.
  ///
  /// Counts exactly the rooms [archivedRooms] is built from — `hidden` and not
  /// in [deletedRoomIds] — with `unreadCount > 0`; same [filter]-independence
  /// and same [includeMuted] policy as [unreadRoomCount], which counts the
  /// complementary (main-list) half.
  ///
  /// Archiving a room keeps its unread count (it is only moved out of the main
  /// list), and an incoming message bumps that count without unarchiving the
  /// room, so `hidden && unreadCount > 0` is a reachable and durable state. Show
  /// this number on the "Archived" section header: a consumer whose badge
  /// counts only [unreadRoomCount] otherwise leaves those rooms with no visible
  /// trace at all.
  int unreadArchivedRoomCount({bool includeMuted = false}) =>
      _countUnread(archived: true, includeMuted: includeMuted);

  int _countUnread({required bool archived, required bool includeMuted}) {
    var count = 0;
    for (final room in _rooms) {
      if (room.hidden != archived) continue;
      if (_isDeleted(room.id)) continue;
      if (room.unreadCount <= 0) continue;
      if (!includeMuted && room.muted) continue;
      count++;
    }
    return count;
  }

  bool _isDeleted(String roomId) => _deletedRoomIds.contains(roomId);

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  String get filter => _filter;
  bool get isSelecting => _selectedIds.isNotEmpty;

  RoomListItem? getRoomById(String roomId) {
    final index = _indexById[roomId];
    return index != null ? _rooms[index] : null;
  }

  int? _findIndex(String roomId) => _indexById[roomId];

  void setRooms(List<RoomListItem> rooms, {int? seq}) {
    _rooms
      ..clear()
      ..addAll(rooms);
    final ids = rooms.map((r) => r.id).toSet();
    _localTouchedAt.removeWhere((id, _) => !ids.contains(id));
    _recordAppliedSeq(seq);
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Upserts [incoming] into the list without ever wiping rows the caller
  /// can't vouch for — the anti-flash counterpart to [setRooms].
  ///
  /// A non-authoritative merge (a cache read, or a partial/best-effort
  /// network response) only ever adds or updates rows; it never drops one,
  /// so a background revalidation that comes back short (or empty, e.g. a
  /// transient error surfaced as an empty page) can't blank out rows the
  /// list already knows are real. An authoritative merge (a full server
  /// snapshot the caller trusts completely) additionally drops any row NOT
  /// present in [incoming] — same end state as [setRooms], but reached by
  /// upserting in place rather than clear-then-refill, so listeners never
  /// observe an empty list between the two.
  ///
  /// [snapshotAt] is the wall-clock time the network snapshot behind
  /// [incoming] was *captured* (i.e. the moment the request went out).
  /// It gates the authoritative drop pass against a stale-snapshot race: a
  /// row created/edited locally *after* that instant (per [_localTouchedAt])
  /// is spared even when [incoming] omits it, because an older in-flight
  /// snapshot simply could not have seen it yet. A row locally touched at or
  /// before [snapshotAt] — or never touched locally at all — is a genuine
  /// server absence and is dropped. `null` disables the guard entirely.
  ///
  /// An authoritative [incoming] is the truth, full stop — including when
  /// it's totally empty: the backend contract is that a successful response
  /// represents the caller's complete room set (a failed/partial read fails
  /// the request outright instead of answering 200), so an empty snapshot
  /// means the user genuinely has zero rooms right now and the list is
  /// cleared to match (still respecting the [snapshotAt] recency guard —
  /// a room created locally during the round-trip is spared). Genuine
  /// removals arrive the same way whether one room or all of them: via
  /// realtime events (`RoomLeft` / `RoomDeleted`), or via any authoritative
  /// snapshot — full or empty — gated by [snapshotAt] above. A
  /// non-authoritative (cache) pass with empty [incoming] is unaffected:
  /// it never drops rows regardless of emptiness (see below).
  ///
  /// [representsCompleteSet] and [seq] gate the destructive drop pass
  /// through [_acceptsPrune] — the same rule [allowsInferredPrune] applies
  /// for other absence-based removals. [representsCompleteSet] `false`
  /// (a filtered or paginated view) never prunes, matching [snapshotAt]'s
  /// existing per-row recency guard but at the whole-pass level. [seq],
  /// reserved via [nextSeq] when the fetch behind [incoming] was
  /// dispatched, additionally denies the drop when a fresher pass already
  /// landed while this one was in flight — a reordered stale result must
  /// only add/update, never undo what the newer pass already established.
  void mergeRooms(
    List<RoomListItem> incoming, {
    required bool authoritative,
    DateTime? snapshotAt,
    int? seq,
    bool representsCompleteSet = true,
  }) {
    final canPrune =
        authoritative &&
        _acceptsPrune(representsCompleteSet: representsCompleteSet, seq: seq);
    var changed = false;
    for (final room in incoming) {
      final index = _indexById[room.id];
      if (index == null) {
        _rooms.add(room);
        changed = true;
      } else if (_rooms[index] != room) {
        _rooms[index] = room;
        changed = true;
      }
      // The server now vouches for this row — drop any local-recency
      // protection so a later authoritative absence can reconcile it.
      if (canPrune) _localTouchedAt.remove(room.id);
    }
    if (canPrune) {
      final incomingIds = incoming.map((r) => r.id).toSet();
      final removedIds = _rooms
          .where(
            (r) =>
                !incomingIds.contains(r.id) &&
                !_isNewerThanSnapshot(r.id, snapshotAt),
          )
          .map((r) => r.id)
          .toList();
      if (removedIds.isNotEmpty) {
        final removed = removedIds.toSet();
        _rooms.removeWhere((r) => removed.contains(r.id));
        for (final id in removedIds) {
          _localTouchedAt.remove(id);
          _selectedIds.remove(id);
          final timers = _typingTimers.remove(id);
          if (timers != null) {
            for (final t in timers.values) {
              t.cancel();
            }
          }
        }
        changed = true;
      }
    }
    _recordAppliedSeq(seq);
    if (!changed) return;
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  bool _isNewerThanSnapshot(String roomId, DateTime? snapshotAt) {
    if (snapshotAt == null) return false;
    final touched = _localTouchedAt[roomId];
    return touched != null && touched.isAfter(snapshotAt);
  }

  void addRoom(RoomListItem room) {
    if (_indexById.containsKey(room.id)) return;
    _rooms.add(room);
    _localTouchedAt[room.id] = DateTime.now();
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void updateRoom(RoomListItem room) {
    final index = _findIndex(room.id);
    if (index == null) return;
    _rooms[index] = room;
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void removeRoom(String roomId) {
    final index = _findIndex(roomId);
    if (index == null) return;
    _rooms.removeAt(index);
    _localTouchedAt.remove(roomId);
    _selectedIds.remove(roomId);
    final timers = _typingTimers.remove(roomId);
    if (timers != null) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Marks [roomId] as per-user deleted and drops its row from the list.
  /// The room is excluded from both [rooms] and [archivedRooms] until
  /// [clearDeleted] runs (peer writes again / unarchive). Mirrors the
  /// persistent `getDeletedRoomIds` set the cache owns.
  void markDeleted(String roomId) {
    final added = _deletedRoomIds.add(roomId);
    final index = _findIndex(roomId);
    if (index != null) {
      _rooms.removeAt(index);
      _localTouchedAt.remove(roomId);
      _selectedIds.remove(roomId);
      final timers = _typingTimers.remove(roomId);
      if (timers != null) {
        for (final t in timers.values) {
          t.cancel();
        }
      }
      _rebuildIndex();
    }
    if (!added && index == null) return;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Clears the per-user deleted flag for [roomId] so it can surface
  /// again. The row itself is re-added by the caller (resurrection
  /// brings it back empty). No-op when the id was not flagged.
  void clearDeleted(String roomId) {
    if (!_deletedRoomIds.remove(roomId)) return;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Folds a room-list pass's persistent deleted set into the in-memory
  /// mirror: [add] is unioned in, and only the ids in [remove] can leave
  /// it. Unlike [setDeletedRoomIds] a pass can never drop an id merely by
  /// not reporting it, so a cache read that came back short does not put
  /// every deleted chat back on screen. Legitimate un-marking is explicit
  /// — the resurrection sweep names the room it revived, and a live
  /// `new_message` goes through [clearDeleted].
  void mergeDeletedRoomIds(Set<String> add, {Set<String> remove = const {}}) {
    var changed = false;
    for (final id in add) {
      if (_deletedRoomIds.add(id)) changed = true;
    }
    for (final id in remove) {
      if (_deletedRoomIds.remove(id)) changed = true;
    }
    if (!changed) return;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Replaces the in-memory deleted set wholesale. Prefer
  /// [mergeDeletedRoomIds]: seeding with this from a cache read makes an
  /// unreadable cache indistinguishable from an empty one.
  void setDeletedRoomIds(Set<String> ids) {
    if (_setEquals(_deletedRoomIds, ids)) return;
    _deletedRoomIds
      ..clear()
      ..addAll(ids);
    _invalidateFilterCache();
    notifyListeners();
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void setFilter(String filter) {
    if (_filter == filter) return;
    _filter = filter;
    _invalidateFilterCache();
    notifyListeners();
  }

  void _invalidateFilterCache() {
    _filterDirty = true;
  }

  void toggleSelect(String roomId) {
    if (_selectedIds.contains(roomId)) {
      _selectedIds.remove(roomId);
    } else {
      _selectedIds.add(roomId);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Marks [userId] as typing (or not) in [roomId]. When typing, the entry
  /// is auto-cleared after [timeout] unless renewed.
  void setRoomTyping(
    String roomId,
    String userId,
    bool isTyping, {
    Duration timeout = const Duration(seconds: 7),
  }) {
    final index = _findIndex(roomId);
    if (index == null) return;
    final room = _rooms[index];
    final current = room.typingUserIds;

    _typingTimers[roomId]?[userId]?.cancel();

    Set<String> next;
    if (isTyping) {
      if (current.contains(userId)) {
        next = current;
      } else {
        next = {...current, userId};
      }
      final timers = _typingTimers.putIfAbsent(roomId, () => {});
      timers[userId] = Timer(timeout, () {
        setRoomTyping(roomId, userId, false);
      });
    } else {
      if (!current.contains(userId)) return;
      next = {...current}..remove(userId);
      _typingTimers[roomId]?.remove(userId);
      if (_typingTimers[roomId]?.isEmpty ?? false) {
        _typingTimers.remove(roomId);
      }
    }

    if (identical(next, current)) return;
    _rooms[index] = room.copyWith(typingUserIds: next);
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Notifies listeners without changing room state. Use after external data
  /// that the tile renders (e.g. cached member display names) has changed and
  /// the visible representation needs to refresh.
  void notifyMembersChanged() {
    notifyListeners();
  }

  void clearAllTyping() {
    for (final timers in _typingTimers.values) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _typingTimers.clear();
    var changed = false;
    for (var i = 0; i < _rooms.length; i++) {
      if (_rooms[i].typingUserIds.isNotEmpty) {
        _rooms[i] = _rooms[i].copyWith(typingUserIds: const <String>{});
        changed = true;
      }
    }
    if (changed) {
      _invalidateFilterCache();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timers in _typingTimers.values) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _typingTimers.clear();
    super.dispose();
  }

  static final _farFuture = DateTime(9999);

  void _sortRooms() {
    _rooms.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final aTime = a.lastMessageTime ?? _farFuture;
      final bTime = b.lastMessageTime ?? _farFuture;
      return bTime.compareTo(aTime);
    });
  }

  void _rebuildIndex() {
    _indexById.clear();
    for (var i = 0; i < _rooms.length; i++) {
      _indexById[_rooms[i].id] = i;
    }
  }
}
