/// Knobs for [RealtimeMode.polling]. Passed via
/// [ChatConfig.pollingConfig] (defaults to `PollingConfig()` when
/// polling is selected without an explicit instance).
///
/// Validation lives in `TransportManager.fromConfig`: an [interval]
/// below 5 seconds is rejected to protect the backend and the device
/// battery from runaway loops.
class PollingConfig {
  /// Cadence between full polls. Defaults to 15 s.
  final Duration interval;

  /// When `true` the engine additionally polls messages for rooms that
  /// currently have an active `ChatController` (the user is viewing
  /// them). Improves perceived latency in the open chat at the cost of
  /// one extra `messages.list` per tick per open room.
  final bool pollOpenRoomMessages;

  /// When `true` only rooms returned by
  /// `rooms.getUserRooms(type: 'unread')` are diffed. When `false` the
  /// engine fetches all rooms — heavier on the backend but covers
  /// "silent" updates (e.g. someone edited a message in a room that has
  /// no unread).
  final bool pollUnreadOnly;

  /// Max rooms to `messages.list` for in a single tick after diff
  /// detection. Protects the backend when the user has many rooms.
  final int maxRoomsPerTick;

  const PollingConfig({
    this.interval = const Duration(seconds: 15),
    this.pollOpenRoomMessages = true,
    this.pollUnreadOnly = true,
    this.maxRoomsPerTick = 10,
  });
}
