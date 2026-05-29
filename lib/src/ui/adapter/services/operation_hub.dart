import 'dart:async';

import '../../../core/result.dart';
import '../operation_error.dart';

/// Owns the two broadcast streams the adapter publishes for
/// cross-cutting concerns: failure stream (snackbars, telemetry) and
/// success stream (confirmation SnackBars in `ChatView`).
///
/// Centralises the "emit a failure / emit a success" patterns so every
/// callsite goes through the same logic — including the
/// "skip if controller already closed" guard that prevents
/// `StateError: Cannot add new events after calling close`
/// during a racing dispose.
class OperationHub {
  OperationHub();

  final StreamController<OperationError> _errors =
      StreamController<OperationError>.broadcast();
  final StreamController<OperationSuccess> _successes =
      StreamController<OperationSuccess>.broadcast();

  /// Broadcast stream of failures from any adapter operation. The
  /// `ChatResult.ChatFailureResult` is still returned to the caller; this stream is
  /// for cross-cutting concerns (global snackbars, telemetry).
  /// Multiple subscribers can listen concurrently.
  Stream<OperationError> get errors => _errors.stream;

  /// Broadcast stream of successful operations with user-visible side
  /// effects worth confirming (pin/unpin, delete, forward, mute…).
  /// `ChatView` subscribes when `showOperationFeedback: true`
  /// (default).
  Stream<OperationSuccess> get successes => _successes.stream;

  /// Adds [result]'s failure to [errors] when it failed, then returns
  /// [result] unchanged so the caller can `return hub.emitFailure(...)`
  /// without losing the success path. Returns ChatSuccess unchanged on
  /// success (no emission).
  ///
  /// No-op (still returns the ChatResult) when the underlying stream
  /// controller is closed — happens during racing dispose.
  ChatResult<T> emitFailure<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) {
    if (result.isFailure && !_errors.isClosed) {
      _errors.add(
        OperationError(
          kind: kind,
          failure: result.failureOrThrow,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
      );
    }
    return result;
  }

  /// Adds an [OperationSuccess] to [successes]. No-op when the stream
  /// is closed (post-dispose).
  void emitSuccess(
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) {
    if (_successes.isClosed) return;
    _successes.add(
      OperationSuccess(
        kind: kind,
        roomId: roomId,
        messageId: messageId,
        userId: userId,
      ),
    );
  }

  /// Closes both stream controllers. Subsequent emit calls are no-ops.
  /// Called from `ChatUiAdapter.dispose()`.
  Future<void> dispose() async {
    await _errors.close();
    await _successes.close();
  }

  /// `true` when [dispose] has been called and both streams are closed.
  /// Diagnostics only.
  bool get isClosed => _errors.isClosed && _successes.isClosed;
}
