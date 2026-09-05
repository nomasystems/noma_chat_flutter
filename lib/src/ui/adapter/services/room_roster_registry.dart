import 'dart:collection';

/// In-memory `roomId → member ids` index, kept so the room list can answer
/// "who is in this room?" synchronously.
///
/// The room list filter runs on every keystroke and cannot await anything, so
/// searching a group by one of its members needs the roster already in
/// memory. This registry holds what the SDK has already seen — the rosters
/// read when a chat, its info page or its member list was opened, plus the
/// join/leave events that arrived afterwards — and answers from that. A room
/// whose roster was never seen simply contributes no members, exactly as
/// before.
///
/// It is a search index, never a source of truth: `members.list` remains the
/// authority on who belongs to a room, and nothing here drives membership,
/// permissions or message delivery.
///
/// Bounded on both axes so a long session or a community-sized group cannot
/// grow it without limit: [maxRooms] rooms are tracked (the least recently
/// recorded one is dropped first) with [maxMembersPerRoom] ids each.
class RoomRosterRegistry {
  RoomRosterRegistry({this.maxRooms = 500, this.maxMembersPerRoom = 512})
    : assert(maxRooms > 0),
      assert(maxMembersPerRoom > 0);

  /// How many rooms keep a roster before the least recently recorded one is
  /// evicted.
  final int maxRooms;

  /// How many member ids one room keeps. A group past this size stops being
  /// fully searchable by member rather than growing without bound.
  final int maxMembersPerRoom;

  final LinkedHashMap<String, Set<String>> _byRoom = LinkedHashMap();

  /// Members known for [roomId], empty when the roster was never seen.
  Set<String> membersOf(String roomId) => _byRoom[roomId] ?? const <String>{};

  /// `true` when a roster has been recorded for [roomId] — as opposed to a
  /// room known to have no members.
  bool knows(String roomId) => _byRoom.containsKey(roomId);

  /// Replaces the roster of [roomId] with [userIds]. Use this for a complete
  /// read (`members.list` with no pagination); [addAll] is the one for a page
  /// or a single join.
  void record(String roomId, Iterable<String> userIds) {
    if (roomId.isEmpty) return;
    _byRoom.remove(roomId);
    _byRoom[roomId] = _capped(_clean(userIds));
    _evictOverflow();
  }

  /// Adds [userIds] to the roster of [roomId], keeping whatever was already
  /// known. Use this for a page of a paginated roster.
  void addAll(String roomId, Iterable<String> userIds) {
    if (roomId.isEmpty) return;
    final clean = _clean(userIds);
    if (clean.isEmpty && _byRoom.containsKey(roomId)) return;
    final current = _byRoom.remove(roomId) ?? <String>{};
    current.addAll(clean);
    _byRoom[roomId] = _capped(current);
    _evictOverflow();
  }

  /// Records a single member of [roomId].
  void add(String roomId, String userId) => addAll(roomId, [userId]);

  /// Drops [userId] from the roster of [roomId]. No-op when the roster was
  /// never seen — a room with an unknown roster stays unknown rather than
  /// becoming an empty one.
  void remove(String roomId, String userId) {
    _byRoom[roomId]?.remove(userId);
  }

  /// Forgets the roster of [roomId], e.g. when the room is deleted or the
  /// user is kicked out of it.
  void forget(String roomId) {
    _byRoom.remove(roomId);
  }

  /// Resets the registry. Called on logout and dispose.
  void clear() => _byRoom.clear();

  /// Diagnostics — number of rooms with a recorded roster.
  int get length => _byRoom.length;

  Set<String> _clean(Iterable<String> userIds) =>
      userIds.where((id) => id.isNotEmpty).toSet();

  Set<String> _capped(Set<String> ids) => ids.length <= maxMembersPerRoom
      ? ids
      : ids.take(maxMembersPerRoom).toSet();

  void _evictOverflow() {
    while (_byRoom.length > maxRooms) {
      _byRoom.remove(_byRoom.keys.first);
    }
  }
}
