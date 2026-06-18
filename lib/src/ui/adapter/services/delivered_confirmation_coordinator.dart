import 'dart:async';

import '../../../client/chat_client.dart';
import '../../../core/result.dart';

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
/// Failures are swallowed into the returned [ChatResult]: a missed
/// delivered confirmation only means the sender sees a single tick for
/// longer — the cursor is re-sent on the next message or on the
/// reconnect catch-up.
class DeliveredConfirmationCoordinator {
  DeliveredConfirmationCoordinator({
    required ChatMessagesApi messages,
    required bool Function() isDisposed,
  }) : _messages = messages,
       _isDisposed = isDisposed;

  final ChatMessagesApi _messages;
  final bool Function() _isDisposed;

  final Map<String, _PendingConfirmation> _inFlight = {};

  /// Fires (or piggybacks on) a `markRoomAsDelivered` for [roomId] with
  /// [messageId] as the delivered cursor. Never throws; no-op (returns
  /// `ChatSuccess(null)`) when [_isDisposed] returns true.
  Future<ChatResult<void>> confirm(String roomId, String messageId) async {
    if (_isDisposed()) return const ChatSuccess(null);

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
    tracker.completer.complete(result);
    _inFlight.remove(roomId);
    final queued = tracker.queuedMessageId;
    if (queued != null && !_isDisposed()) {
      unawaited(confirm(roomId, queued));
    }
    return result;
  }

  /// Diagnostics — number of rooms with an in-flight confirmation.
  int get inFlightCount => _inFlight.length;
}

/// Tracks an in-flight confirmation so successive requests for the
/// same room can be coalesced onto the leader.
class _PendingConfirmation {
  final Completer<ChatResult<void>> completer = Completer<ChatResult<void>>();
  String? queuedMessageId;
}
