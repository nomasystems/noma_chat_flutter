import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../events/chat_event.dart';

/// Coordinates `messages.markRoomAsDelivered` calls with per-room
/// coalescing so a burst of `NewMessageEvent` in a room doesn't fan
/// into one confirmation per message.
///
/// **Invariant**: at most one in-flight confirmation per room.
/// Concurrent callers piggyback on the same `Future`. The freshest
/// `messageId` requested while the leader is in flight is stashed and
/// fired as a follow-up once the leader resolves — the server always
/// learns the newest cursor while older intermediate ids are silently
/// dropped (cursors are max-registers, so they carry no information).
/// A burst therefore costs at most two confirmations.
///
/// **Repeat suppression**: a cursor already confirmed for a room is
/// never re-sent. The room-list sync fires one confirmation per unread
/// room on its cache pass AND again on its network pass (and once more
/// per background revalidation / screen reopen), all with the same
/// `lastMessageId`; the server max-merges them, so every repeat after
/// the first success is a pure waste of a request.
///
/// Failures are swallowed into the returned [ChatResult]: a missed
/// delivered confirmation only means the sender sees a single tick for
/// longer — the cursor is re-sent on the next message or on the
/// reconnect catch-up.
class DeliveredConfirmationCoordinator {
  DeliveredConfirmationCoordinator({
    required ChatMessagesApi messages,
    required bool Function() isDisposed,
    ValueListenable<ChatConnectionState>? connectionState,
  }) : _messages = messages,
       _isDisposed = isDisposed,
       _connectionState = connectionState;

  final ChatMessagesApi _messages;
  final bool Function() _isDisposed;

  /// Realtime connection state the [confirm] network gate reads — pass the
  /// adapter's `connectionStateNotifier` here. When `null` the gate is
  /// disabled and [confirm] always hits the network (legacy behaviour,
  /// kept so a host that builds this coordinator standalone is unaffected).
  final ValueListenable<ChatConnectionState>? _connectionState;

  final Map<String, _PendingConfirmation> _inFlight = {};

  /// Newest cursor already acknowledged by the server, per room. Read by
  /// the repeat-suppression gate in [confirm]; only successful results are
  /// recorded, so a failed confirmation is always retried.
  final Map<String, String> _confirmedCursors = {};

  /// Fires (or piggybacks on) a `markRoomAsDelivered` for [roomId] with
  /// [messageId] as the delivered cursor. Never throws; no-op (returns
  /// `ChatSuccess(null)`) when [_isDisposed] returns true, when
  /// [messageId] was already confirmed for [roomId], or — when a
  /// connection state was injected — when the transport is not connected,
  /// in which case a [NetworkFailure] result is returned without touching
  /// the network. Dropping an offline confirmation is safe: the adapter
  /// re-runs the room sync (and therefore this call) on every reconnect.
  Future<ChatResult<void>> confirm(String roomId, String messageId) async {
    if (_isDisposed()) return const ChatSuccess(null);
    if (!_transportIsConnected) {
      return const ChatFailureResult<void>(
        NetworkFailure('delivered confirmation skipped: transport offline'),
      );
    }
    if (_confirmedCursors[roomId] == messageId) return const ChatSuccess(null);

    final pending = _inFlight[roomId];
    if (pending != null) {
      pending.queuedMessageId = messageId;
      return pending.completer.future;
    }

    final tracker = _PendingConfirmation();
    _inFlight[roomId] = tracker;
    ChatResult<void> result;
    try {
      result = await _messages.markRoomAsDelivered(
        roomId,
        lastDeliveredMessageId: messageId,
      );
    } catch (_) {
      result = const ChatFailureResult<void>(
        UnexpectedFailure('delivered confirmation failed'),
      );
    }
    if (result.isSuccess) _confirmedCursors[roomId] = messageId;
    tracker.completer.complete(result);
    _inFlight.remove(roomId);
    final queued = tracker.queuedMessageId;
    if (queued != null && !_isDisposed()) {
      unawaited(confirm(roomId, queued));
    }
    return result;
  }

  bool get _transportIsConnected {
    final state = _connectionState;
    return state == null || state.value.isConnected;
  }

  /// Forgets every already-confirmed cursor so the next [confirm] for each
  /// room hits the network again. Call it whenever the identity behind the
  /// confirmations changes or their target may have been reset — `signOut`
  /// and user switches — since the suppression map is keyed by room id
  /// alone and would otherwise leak across sessions.
  void reset() => _confirmedCursors.clear();

  /// Diagnostics — number of rooms with an in-flight confirmation.
  int get inFlightCount => _inFlight.length;

  /// Diagnostics — number of rooms with a recorded confirmed cursor.
  int get confirmedCursorCount => _confirmedCursors.length;
}

/// Tracks an in-flight confirmation so successive requests for the
/// same room can be coalesced onto the leader.
class _PendingConfirmation {
  final Completer<ChatResult<void>> completer = Completer<ChatResult<void>>();
  String? queuedMessageId;
}
