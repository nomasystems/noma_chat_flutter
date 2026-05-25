/// How the SDK should establish its real-time channel against the
/// backend. Selected via [ChatConfig.realtimeMode].
///
/// Defaults to [auto], which preserves the historical behaviour: WS as
/// primary, SSE as fallback after a WS failure. The other modes are
/// opt-in for hostile networks, constrained backends, debugging or
/// low-power devices.
///
/// See `info/noma-chat/ARCHITECTURE.md` ("Transportes en tiempo real")
/// for the trade-off matrix, and `.claude/plans/realtime_modes.md` for
/// the design notes.
enum RealtimeMode {
  /// WS primary + SSE fallback after a WS failure. Recommended default.
  auto,

  /// WS only. Reconnect WS forever if it drops; never fall back to SSE.
  /// Use when the backend WS endpoint is known-reliable and degrading
  /// to SSE is unwanted (e.g. you'd rather surface the outage).
  webSocketOnly,

  /// SSE only. Skip the WS connect attempt entirely. Use behind
  /// proxies/CDNs that block HTTP→WS upgrades, or when you want to
  /// avoid the WS round-trip in browsers.
  serverSentEventsOnly,

  /// REST polling at a fixed interval. No streaming. Last-resort
  /// fallback for very hostile networks or backends without push.
  /// Battery cost is higher; typing/presence are unavailable. Reactions
  /// and message edits on existing messages are NOT reflected live (only
  /// on a fresh chat reload) — the poll reconciles room-list fields and
  /// new messages, not per-message changes. Presence "online" is kept
  /// alive by a lightweight heartbeat on each poll. Use `auto` if you
  /// need live reactions/edits/typing.
  polling,

  /// No background channel. Updates only arrive when the app calls
  /// `NomaChat.refresh()` / `refreshRoom(roomId)` (typically wired to
  /// pull-to-refresh). Use for low-power, demos or e-readers. Same
  /// per-message caveat as [polling]: reactions and edits on existing
  /// messages appear only on a fresh reload, not live. Presence is
  /// action-driven — a heartbeat fires on connect and on each refresh,
  /// so the user shows online for a short TTL after an action.
  manual,
}
