import '../../../client/chat_client.dart';
import '../../../models/presence.dart';
import '../../controller/room_list_controller.dart';
import 'dm_contact_registry.dart';

/// Owns the presence cache and the bootstrap/refresh logic that keeps
/// it in sync with the server. Subscribes to `PresenceChangedEvent`s
/// via the adapter's event router (which calls [update]) and exposes
/// `presenceFor(userId)` for read-back.
///
/// Dependencies arrive by constructor so the bootstrap is testable
/// with a mock `ChatPresenceApi` + an empty `RoomListController`.
///
/// Failures from `presence.getAll()` are logged via [logger] and
/// swallowed — presence is best-effort cosmetic state, not a
/// correctness contract.
class PresenceRegistry {
  PresenceRegistry({
    required ChatPresenceApi api,
    required RoomListController roomList,
    required DmContactRegistry dmContacts,
    required bool Function() isDisposed,
    void Function(String level, String message)? logger,
  }) : _api = api,
       _roomList = roomList,
       _dmContacts = dmContacts,
       _isDisposed = isDisposed,
       _logger = logger;

  final ChatPresenceApi _api;
  final RoomListController _roomList;
  final DmContactRegistry _dmContacts;
  final bool Function() _isDisposed;
  final void Function(String level, String message)? _logger;

  final Map<String, ChatPresence> _cache = {};

  /// Cached snapshot for [userId], or `null` when no presence event
  /// has landed (or no bootstrap fetch succeeded) for that user yet.
  ChatPresence? presenceFor(String userId) => _cache[userId];

  /// Best-effort refresh of the presence cache. Used after a
  /// (re)connection so contact online-state reflects the current
  /// server snapshot — CHT does not re-emit `presence_changed` for
  /// users whose state was already known before the disconnect.
  /// Failures are logged and swallowed.
  Future<void> bootstrap() async {
    try {
      final res = await _api.getAll();
      if (_isDisposed()) return;
      final bulk = res.dataOrNull;
      if (bulk == null) return;
      for (final p in bulk.contacts) {
        _cache[p.userId] = p;
      }
      for (final room in _roomList.allRooms) {
        if (room.isGroup) continue;
        final otherUserId = room.otherUserId;
        if (otherUserId == null) continue;
        final p = _cache[otherUserId];
        if (p == null) continue;
        _roomList.updateRoom(
          room.copyWith(isOnline: p.online, presenceStatus: p.status),
        );
      }
    } catch (e) {
      _logger?.call('warn', 'Failed to bootstrap chat presence: $e');
    }
  }

  /// Applies an incoming `PresenceChangedEvent`. Updates the cache
  /// and the matching `RoomListItem` of the user's DM (when one is
  /// registered in [DmContactRegistry]).
  void update(String userId, bool online, PresenceStatus status) {
    _cache[userId] = ChatPresence(
      userId: userId,
      online: online,
      status: status,
    );
    final roomId = _dmContacts.roomIdFor(userId);
    if (roomId == null) return;
    final room = _roomList.getRoomById(roomId);
    if (room == null || room.isGroup) return;
    _roomList.updateRoom(
      room.copyWith(isOnline: online, presenceStatus: status),
    );
  }

  /// Clears the presence cache. Called from `signOut()` / `dispose()`.
  void clear() {
    _cache.clear();
  }

  /// Diagnostics — number of cached presence entries.
  int get length => _cache.length;
}
