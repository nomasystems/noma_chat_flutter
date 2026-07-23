import '../../../client/chat_client.dart';
import '../../../models/presence.dart';
import '../../../observability/chat_logger.dart';
import '../../controller/room_list_controller.dart';
import '../../models/room_list_item.dart';
import 'dm_contact_registry.dart';

/// Owns the presence cache and the bootstrap/refresh logic that keeps
/// it in sync with the server. Subscribes to `PresenceChangedEvent`s
/// via the adapter's event router (which calls [update]) and exposes
/// `presenceFor(userId)` for read-back.
///
/// Dependencies arrive by constructor so the bootstrap is testable
/// with a mock `ChatPresenceApi` + an empty `RoomListController`.
///
/// Failures from `presence.getAll()` are logged via [logs] (tagged
/// [ChatLogTag.presence]) and swallowed — presence is best-effort
/// cosmetic state, not a correctness contract.
class PresenceRegistry {
  PresenceRegistry({
    required ChatPresenceApi api,
    required RoomListController roomList,
    required DmContactRegistry dmContacts,
    required bool Function() isDisposed,
    ChatLogger? logs,
  }) : _api = api,
       _roomList = roomList,
       _dmContacts = dmContacts,
       _isDisposed = isDisposed,
       _logs = logs;

  final ChatPresenceApi _api;
  final RoomListController _roomList;
  final DmContactRegistry _dmContacts;
  final bool Function() _isDisposed;
  final ChatLogger? _logs;

  final Map<String, ChatPresence> _cache = {};

  /// Wall-clock time a live [update] last wrote each user's presence.
  /// [bootstrap] compares this against the instant it began fetching so a
  /// `PresenceChangedEvent` that lands *during* the (awaited) snapshot fetch
  /// is not clobbered by the older snapshot when it resolves — last-writer
  /// by event recency, not by arrival order.
  final Map<String, DateTime> _liveUpdatedAt = {};

  /// Cached snapshot for [userId], or `null` when no presence event
  /// has landed (or no bootstrap fetch succeeded) for that user yet.
  ChatPresence? presenceFor(String userId) => _cache[userId];

  /// Best-effort refresh of the presence cache. Used after a
  /// (re)connection so contact online-state reflects the current
  /// server snapshot — CHT does not re-emit `presence_changed` for
  /// users whose state was already known before the disconnect.
  /// Failures are logged and swallowed.
  ///
  /// Applies every affected room in a single [RoomListController.mergeRooms]
  /// call instead of one [RoomListController.updateRoom] per room: each
  /// `updateRoom` re-sorts and re-indexes the whole list and notifies
  /// listeners synchronously, so doing that once per DM room turns a
  /// reconnection with N rooms into an O(n² log n) sequence of rebuilds
  /// (and N `RoomListView` repaints) instead of one.
  Future<void> bootstrap() async {
    try {
      final startedAt = DateTime.now();
      final res = await _api.getAll();
      if (_isDisposed()) return;
      final bulk = res.dataOrNull;
      if (bulk == null) return;
      for (final p in bulk.contacts) {
        // A live event that landed for this user during the fetch is fresher
        // than the snapshot — never overwrite it with the older value.
        if (_isStaleAgainstLiveUpdate(p.userId, startedAt)) continue;
        _cache[p.userId] = p;
      }
      final updated = <RoomListItem>[];
      for (final room in _roomList.allRooms) {
        if (room.isGroup) continue;
        final otherUserId = room.otherUserId;
        if (otherUserId == null) continue;
        final p = _cache[otherUserId];
        if (p == null) continue;
        if (room.isOnline == p.online &&
            room.presenceStatus == p.status &&
            room.lastSeen == p.lastSeen) {
          continue;
        }
        updated.add(
          room.copyWith(
            isOnline: p.online,
            presenceStatus: p.status,
            lastSeen: p.lastSeen,
          ),
        );
      }
      if (updated.isEmpty) return;
      _roomList.mergeRooms(updated, authoritative: false);
    } catch (e) {
      _logs?.presence(ChatLogLevel.warn, 'Failed to bootstrap chat presence: $e');
    }
  }

  bool _isStaleAgainstLiveUpdate(String userId, DateTime snapshotStartedAt) {
    final live = _liveUpdatedAt[userId];
    return live != null && live.isAfter(snapshotStartedAt);
  }

  /// Applies an incoming `PresenceChangedEvent`. Updates the cache
  /// and the matching `RoomListItem` of the user's DM (when one is
  /// registered in [DmContactRegistry]).
  void update(
    String userId,
    bool online,
    PresenceStatus status, {
    DateTime? lastSeen,
  }) {
    _cache[userId] = ChatPresence(
      userId: userId,
      online: online,
      status: status,
      lastSeen: lastSeen,
    );
    _liveUpdatedAt[userId] = DateTime.now();
    final roomId = _dmContacts.roomIdFor(userId);
    if (roomId == null) return;
    final room = _roomList.getRoomById(roomId);
    if (room == null || room.isGroup) return;
    _roomList.updateRoom(
      room.copyWith(isOnline: online, presenceStatus: status, lastSeen: lastSeen),
    );
  }

  /// Clears the presence cache. Called from `signOut()` / `dispose()`.
  void clear() {
    _cache.clear();
    _liveUpdatedAt.clear();
  }

  /// Diagnostics — number of cached presence entries.
  int get length => _cache.length;
}
