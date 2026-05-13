part of 'chat_ui_adapter.dart';

/// Owns the presence cache and the bootstrap/refresh logic that keeps it in
/// sync with the server. Lives as a `part of` the adapter library so it can
/// read the adapter's private state (`client`, `roomListController`,
/// `_dmRoomByContact`, `_disposed`, `logger`) without an explicit
/// dependency-injection ceremony — every collaborator in this folder is an
/// internal helper of the adapter, never re-exported.
class _PresenceManager {
  _PresenceManager(this._adapter);

  final ChatUiAdapter _adapter;
  final Map<String, ChatPresence> _cache = {};

  ChatPresence? presenceFor(String userId) => _cache[userId];

  /// Best-effort refresh of the presence cache. Used after a (re)connection
  /// so that the contact online-state reflects the current server snapshot
  /// — CHT does not re-emit `presence_changed` for users whose state was
  /// already known before the disconnect. Failures are logged and swallowed.
  Future<void> bootstrap() async {
    try {
      final res = await _adapter.client.presence.getAll();
      if (_adapter._disposed) return;
      final bulk = res.dataOrNull;
      if (bulk == null) return;
      for (final p in bulk.contacts) {
        _cache[p.userId] = p;
      }
      for (final room in _adapter.roomListController.allRooms) {
        if (room.isGroup) continue;
        final otherUserId = room.otherUserId;
        if (otherUserId == null) continue;
        final p = _cache[otherUserId];
        if (p == null) continue;
        _adapter.roomListController.updateRoom(
          room.copyWith(isOnline: p.online, presenceStatus: p.status),
        );
      }
    } catch (e) {
      _adapter.logger?.call('warn', 'Failed to bootstrap chat presence: $e');
    }
  }

  /// Apply an incoming `PresenceChangedEvent`. Updates the cache and the
  /// `RoomListItem` of the corresponding DM (if registered).
  void update(String userId, bool online, PresenceStatus status) {
    _cache[userId] = ChatPresence(
      userId: userId,
      online: online,
      status: status,
    );
    final roomId = _adapter._dmRoomByContact[userId];
    if (roomId == null) return;
    final room = _adapter.roomListController.getRoomById(roomId);
    if (room == null || room.isGroup) return;
    _adapter.roomListController.updateRoom(
      room.copyWith(isOnline: online, presenceStatus: status),
    );
  }
}
