/// What [ChatUiAdapter] does to the realtime connection when the host app
/// goes to the background, under [ChatLifecyclePolicy.onPause].
enum ChatPauseAction {
  /// Leave the WebSocket connected while backgrounded (WhatsApp-like).
  /// Realtime events keep arriving; the OS may still suspend the socket on
  /// its own (network handoff, aggressive background killing), in which
  /// case the pong watchdog + reconnect-on-resume recovers it.
  keepAlive,

  /// Disconnect after [ChatLifecyclePolicy.pauseGracePeriod] elapses in the
  /// background. Useful for hosts that suppress push notifications while a
  /// realtime connection is active and want that suppression to lift
  /// shortly after backgrounding.
  disconnect,
}

/// Governs how `ChatUiAdapter` reacts to app foreground/background
/// transitions when it manages its own `WidgetsBindingObserver`
/// (`manageAppLifecycle: true` on the adapter / `NomaChat.create`).
///
/// Two ready-made policies cover the common cases:
/// * [ChatLifecyclePolicy.standard] — WhatsApp-like: stay connected in the
///   background, reconnect + resync on resume.
/// * [ChatLifecyclePolicy.pushOptimized] — disconnect shortly after
///   backgrounding (for hosts that suppress push while a realtime
///   connection is active), reconnect + resync on resume.
class ChatLifecyclePolicy {
  const ChatLifecyclePolicy({
    this.reconnectOnResume = true,
    this.onPause = ChatPauseAction.keepAlive,
    this.pauseGracePeriod = const Duration(seconds: 3),
    this.resyncOnResume = true,
  });

  /// WhatsApp-like default: keep the connection alive in the background,
  /// reconnect and resync on resume.
  const ChatLifecyclePolicy.standard() : this();

  /// Disconnects [pauseGracePeriod] after the app is backgrounded. Intended
  /// for hosts whose push-notification pipeline suppresses pushes while a
  /// realtime connection is open and rely on disconnecting promptly to
  /// resume receiving them. The room list stays populated regardless (the
  /// adapter's `disconnect()` no longer clears it) and `resync()` on resume
  /// backfills anything missed.
  const ChatLifecyclePolicy.pushOptimized()
    : this(onPause: ChatPauseAction.disconnect);

  /// Reconnect when the app returns to the foreground. Defaults to `true`;
  /// disable only if the host drives reconnection itself.
  final bool reconnectOnResume;

  /// What to do when the app is backgrounded. Defaults to [
  /// ChatPauseAction.keepAlive].
  final ChatPauseAction onPause;

  /// When [onPause] is [ChatPauseAction.disconnect], how long to wait in
  /// the background before disconnecting — avoids tearing down the socket
  /// for a brief app-switcher glance. Ignored under [ChatPauseAction
  /// .keepAlive]. Defaults to 3 seconds.
  final Duration pauseGracePeriod;

  /// Whether a resume-triggered reconnect should also resync (room list +
  /// active room + presence). Declarative — the actual resync trigger is
  /// centralized in the adapter's reconnect hook (`ChatUiAdapter.resync`)
  /// rather than fired separately here, so a resume racing an
  /// already-in-flight reconnect can't double-resync. Kept as an explicit
  /// field so a policy can document intent even though today both
  /// built-in policies leave it at the default. Defaults to `true`.
  final bool resyncOnResume;
}
