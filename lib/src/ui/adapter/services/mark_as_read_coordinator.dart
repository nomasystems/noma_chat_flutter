import 'dart:async';

import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../operation_error.dart';

/// Coordinates `messages.markRoomAsRead` REST calls with per-room
/// coalescing so a burst of `NewMessageEvent` in an active room
/// doesn't fan into one HTTP request per message.
///
/// **Invariant**: at most one in-flight `markRoomAsRead` per room.
/// Concurrent callers piggyback on the same `Future`. The freshest
/// `lastReadMessageId` requested while the leader is in flight is
/// stashed and fired as a follow-up once the leader resolves — the
/// server always learns the latest high-water mark even though older
/// intermediate ids are silently dropped.
///
/// Owns the per-room coalescing so callers can fire-and-forget
/// `markAsRead(...)` without worrying about in-flight requests.
class MarkAsReadCoordinator {
  MarkAsReadCoordinator({
    required ChatMessagesApi messages,
    required bool Function() isDisposed,
    required void Function(String roomId) onMarkedRead,
    required ChatResult<T> Function<T>(
      ChatResult<T> result,
      OperationKind kind, {
      String? roomId,
      String? messageId,
      String? userId,
    })
    emitFailure,
  }) : _messages = messages,
       _isDisposed = isDisposed,
       _onMarkedRead = onMarkedRead,
       _emitFailure = emitFailure;

  final ChatMessagesApi _messages;
  final bool Function() _isDisposed;
  final void Function(String roomId) _onMarkedRead;
  final ChatResult<T> Function<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  })
  _emitFailure;

  final Map<String, _PendingMarkAsRead> _inFlight = {};

  /// Fires (or piggybacks on) a `markRoomAsRead` for [roomId]. When
  /// another call for the same room is already in flight, this
  /// returns the same Future as the leader and stashes
  /// [lastReadMessageId] as the latest high-water mark — the leader
  /// fires a follow-up with that id once it completes.
  ///
  /// Always returns the same shape — a `ChatResult<void>` — so callers
  /// can `await` without caring whether they were the leader or a
  /// piggyback.
  ///
  /// No-op (returns `ChatSuccess(null)`) when [_isDisposed] returns true.
  Future<ChatResult<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    if (_isDisposed()) return const ChatSuccess(null);

    final pending = _inFlight[roomId];
    if (pending != null) {
      pending.queuedMessageId = lastReadMessageId;
      pending.hasQueued = true;
      return pending.completer.future;
    }

    final tracker = _PendingMarkAsRead();
    _inFlight[roomId] = tracker;
    try {
      final result = await _messages.markRoomAsRead(
        roomId,
        lastReadMessageId: lastReadMessageId,
      );
      if (!_isDisposed() && result.isSuccess) {
        _onMarkedRead(roomId);
      }
      // A 403/404 here means the user is no longer a member of the room —
      // they just left it or were removed. Marking it read is moot, so
      // swallow it silently instead of surfacing it through `onError`
      // (it was popping a spurious "403 on mark as read" right after a
      // leave/kick). Any other failure still flows through normally.
      final failure = result.failureOrNull;
      if (failure is ForbiddenFailure || failure is NotFoundFailure) {
        tracker.completer.complete(const ChatSuccess(null));
        return const ChatSuccess(null);
      }
      final emitted = _emitFailure(
        result,
        OperationKind.markAsRead,
        roomId: roomId,
      );
      tracker.completer.complete(emitted);
      return emitted;
    } catch (e, stack) {
      tracker.completer.completeError(e, stack);
      rethrow;
    } finally {
      _inFlight.remove(roomId);
      // Drain the queued high-water mark, if any, after releasing
      // the slot so the next call enters cleanly.
      if (tracker.hasQueued && !_isDisposed()) {
        unawaited(
          markAsRead(roomId, lastReadMessageId: tracker.queuedMessageId),
        );
      }
    }
  }

  /// Diagnostics — number of rooms with an in-flight markAsRead.
  int get inFlightCount => _inFlight.length;
}

/// Tracks an in-flight `markAsRead` so successive requests for the
/// same room can be coalesced.
class _PendingMarkAsRead {
  final Completer<ChatResult<void>> completer = Completer<ChatResult<void>>();
  String? queuedMessageId;
  bool hasQueued = false;
}
