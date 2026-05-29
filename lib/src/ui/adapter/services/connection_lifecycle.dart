import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/result.dart';
import '../../../events/chat_event.dart';

/// Owns the lifecycle-related state of the adapter: the two public
/// notifiers (`connectionState`, `initialized`), the disposal flag,
/// and the in-flight `loadRooms` completer used for deduplication.
///
/// The stream subscriptions to `client.events` / `client.stateChanges`
/// stay in the adapter — they're tied to the client API surface
/// rather than to the adapter's lifecycle alone, and the adapter
/// already owns the `_cancelSubscriptions()` helper that handles
/// their teardown.
///
/// The disposal flag flows through every async path on the adapter
/// (`if (lifecycle.isDisposed) return`) so callsites can early-out
/// when the user has torn down the adapter mid-flight. Setting the
/// flag is the first step of [dispose] so anything racing after sees
/// `true` immediately.
class ConnectionLifecycle {
  ConnectionLifecycle({
    ChatConnectionState initialState = ChatConnectionState.disconnected,
  }) : connectionState = ValueNotifier(initialState),
       initialized = ValueNotifier(false);

  /// Notifier for the current realtime connection state. Public on
  /// the adapter as `connectionStateNotifier`.
  final ValueNotifier<ChatConnectionState> connectionState;

  /// `true` once the first successful room load completes (used by
  /// `_RoomEnricher` to skip the network round-trip on subsequent
  /// loads when WS is already streaming events).
  final ValueNotifier<bool> initialized;

  bool _disposed = false;

  /// `true` after [dispose] has been called. Async work captures this
  /// to bail early when the adapter has been torn down mid-flight.
  bool get isDisposed => _disposed;

  /// Completer for the in-flight `loadRooms` call, used to deduplicate
  /// concurrent invocations (a second `loadRooms()` while one is in
  /// flight returns the same future). `null` when no load is active.
  Completer<ChatResult<void>>? pendingLoadRooms;

  /// Marks the lifecycle disposed and tears down the notifiers.
  /// Idempotent — second call is a silent no-op (the `_disposed`
  /// flag latches forever once set).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    initialized.dispose();
    connectionState.dispose();
  }
}
