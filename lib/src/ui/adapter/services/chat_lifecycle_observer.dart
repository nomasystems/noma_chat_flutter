import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../config/lifecycle_policy.dart';

/// `WidgetsBindingObserver` that drives `ChatUiAdapter`'s own app-lifecycle
/// management (`manageAppLifecycle: true`, the default). Never calls
/// `resync()` itself — that stays centralized in the adapter's existing
/// reconnect hook (`_onConnected`) so a resume racing an already-in-flight
/// reconnect can't trigger it twice; this class only decides when to
/// `connect()` / `disconnect()` per [policy].
class ChatLifecycleObserver extends WidgetsBindingObserver {
  ChatLifecycleObserver({
    required this.policy,
    required this.onResume,
    required this.onPause,
  });

  final ChatLifecyclePolicy policy;

  /// Invoked on `AppLifecycleState.resumed` when `policy.reconnectOnResume`
  /// is `true`. Typically `adapter.connect` — a no-op if already connected.
  final void Function() onResume;

  /// Invoked `policy.pauseGracePeriod` after the app is backgrounded, only
  /// when `policy.onPause == ChatPauseAction.disconnect`. Typically
  /// `adapter.disconnect`.
  final void Function() onPause;

  Timer? _pauseTimer;
  bool _attached = false;

  /// Registers this observer with `WidgetsBinding`. Safe to call more than
  /// once (idempotent). No-op — instead of throwing — when no Flutter
  /// binding is initialized yet (e.g. a `ChatUiAdapter` built inside a
  /// plain, non-widget unit test): there is no app lifecycle to observe in
  /// that context, so silently skipping registration is the correct
  /// behavior rather than crashing the caller.
  void attach() {
    if (_attached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } catch (_) {
      // No binding available — nothing to observe.
    }
  }

  /// Reverses [attach]. Safe to call even if [attach] never actually
  /// registered (no-op).
  void detach() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (!_attached) return;
    _attached = false;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Binding already torn down — nothing to remove.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _pauseTimer?.cancel();
        _pauseTimer = null;
        if (policy.reconnectOnResume) onResume();
      case AppLifecycleState.paused:
        _armPauseTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _armPauseTimer() {
    if (policy.onPause != ChatPauseAction.disconnect) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(policy.pauseGracePeriod, onPause);
  }
}
