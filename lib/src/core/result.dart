/// Represents the outcome of an SDK operation: either [ChatSuccess] with data or [ChatFailureResult] with a [ChatFailure].
///
/// Use [fold] to handle both cases, or check [isSuccess]/[isFailure] and access
/// [dataOrNull]/[failureOrNull] directly.
sealed class ChatResult<T> {
  const ChatResult();

  bool get isSuccess => this is ChatSuccess<T>;
  bool get isFailure => this is ChatFailureResult<T>;

  T? get dataOrNull => switch (this) {
    ChatSuccess(data: final d) => d,
    ChatFailureResult() => null,
  };

  ChatFailure? get failureOrNull => switch (this) {
    ChatSuccess() => null,
    ChatFailureResult(failure: final f) => f,
  };

  R fold<R>(
    R Function(ChatFailure failure) onFailure,
    R Function(T data) onSuccess,
  ) => switch (this) {
    ChatSuccess(data: final d) => onSuccess(d),
    ChatFailureResult(failure: final f) => onFailure(f),
  };

  ChatResult<R> map<R>(R Function(T data) transform) => switch (this) {
    ChatSuccess(data: final d) => ChatSuccess(transform(d)),
    ChatFailureResult(failure: final f) => ChatFailureResult(f),
  };

  Future<ChatResult<R>> flatMap<R>(
    Future<ChatResult<R>> Function(T data) transform,
  ) async => switch (this) {
    ChatSuccess(data: final d) => await transform(d),
    ChatFailureResult(failure: final f) => ChatFailureResult(f),
  };

  /// Returns the wrapped data, or [fallback] when this is a [ChatFailureResult].
  /// Convenience for `result.fold((_) => fallback, (d) => d)` when the
  /// caller just wants a sane default and doesn't care about the
  /// failure shape.
  T getOrElse(T fallback) => switch (this) {
    ChatSuccess(data: final d) => d,
    ChatFailureResult() => fallback,
  };

  /// Returns the wrapped data, or computes one from the [failure]. Use
  /// when the fallback depends on what went wrong (e.g. partial cache
  /// after a network error).
  T getOrElseLazy(T Function(ChatFailure failure) onFailure) => switch (this) {
    ChatSuccess(data: final d) => d,
    ChatFailureResult(failure: final f) => onFailure(f),
  };

  /// Returns the wrapped data, throwing [StateError] when this is a
  /// [ChatFailureResult]. Use only when the caller has already verified
  /// `isSuccess` (`when`/`if-case`) and wants the unwrap to be a
  /// programmer error if it isn't. Prefer [fold] / [getOrElse] in
  /// normal code.
  T get dataOrThrow => switch (this) {
    ChatSuccess(data: final d) => d,
    ChatFailureResult(failure: final f) => throw StateError(
      'dataOrThrow on ChatFailureResult: $f',
    ),
  };

  /// Returns the wrapped failure, throwing [StateError] when this is a
  /// [ChatSuccess]. Symmetric to [dataOrThrow]. Use after an `isFailure`
  /// check when you need the failure for typed propagation; prefer
  /// [castFailure] when the goal is just to rewrap the failure with a
  /// different success type.
  ChatFailure get failureOrThrow => switch (this) {
    ChatFailureResult(failure: final f) => f,
    ChatSuccess() => throw StateError('failureOrThrow on ChatSuccess'),
  };

  /// Re-wraps a [ChatFailureResult] under a new success type [R]. Throws
  /// [StateError] when this is a [ChatSuccess]. Replaces the common idiom
  /// `ChatFailureResult<R>(result.failureOrNull!)` after an `isFailure` check.
  ChatResult<R> castFailure<R>() => switch (this) {
    ChatFailureResult(failure: final f) => ChatFailureResult<R>(f),
    ChatSuccess() => throw StateError('castFailure on ChatSuccess'),
  };

  /// Transforms the failure side of a [ChatResult] without touching the
  /// success side. Useful for wrapping a low-level [ChatFailure] in a
  /// domain-specific one before propagating.
  ChatResult<T> mapFailure(
    ChatFailure Function(ChatFailure failure) transform,
  ) => switch (this) {
    ChatSuccess(data: final d) => ChatSuccess(d),
    ChatFailureResult(failure: final f) => ChatFailureResult(transform(f)),
  };
}

/// A successful result containing [data].
final class ChatSuccess<T> extends ChatResult<T> {
  final T data;

  const ChatSuccess(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatSuccess<T> && other.data == data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'ChatSuccess($data)';
}

/// A failed result containing a [ChatFailure] describing what went wrong.
final class ChatFailureResult<T> extends ChatResult<T> {
  final ChatFailure failure;

  const ChatFailureResult(this.failure);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatFailureResult<T> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'ChatFailureResult($failure)';
}

/// Base class for all SDK failure types.
sealed class ChatFailure {
  final String message;

  const ChatFailure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Authentication failed (401). Token may be expired or invalid.
final class AuthFailure extends ChatFailure {
  const AuthFailure([super.message = 'Authentication failed']);
}

/// User lacks permission for the requested operation (403).
final class ForbiddenFailure extends ChatFailure {
  final int statusCode;
  final dynamic body;

  const ForbiddenFailure({
    this.statusCode = 403,
    this.body,
    String message = 'Forbidden',
  }) : super(message);
}

/// Requested resource does not exist (404).
final class NotFoundFailure extends ChatFailure {
  const NotFoundFailure([super.message = 'Not found']);
}

/// Request parameters are invalid (400). Check [errors] for field-level details.
final class ValidationFailure extends ChatFailure {
  final Map<String, dynamic>? errors;

  const ValidationFailure({String message = 'Validation failed', this.errors})
    : super(message);
}

/// Message blocked by a server-side content filter (400).
final class ContentFilterFailure extends ChatFailure {
  const ContentFilterFailure([
    super.message = 'Message blocked by content filter',
  ]);
}

/// Resource already exists or conflicts with current state (409).
final class ConflictFailure extends ChatFailure {
  const ConflictFailure([super.message = 'Conflict']);
}

/// Network is unreachable or the connection was lost.
final class NetworkFailure extends ChatFailure {
  const NetworkFailure([super.message = 'Network error']);
}

/// Server returned a 5xx error.
final class ServerFailure extends ChatFailure {
  final int statusCode;
  final dynamic body;

  const ServerFailure({
    required this.statusCode,
    this.body,
    String message = 'Server error',
  }) : super(message);
}

/// Too many requests (429). Check [retryAfter] for the suggested wait time.
final class RateLimitFailure extends ChatFailure {
  final Duration? retryAfter;

  const RateLimitFailure({
    this.retryAfter,
    String message = 'Rate limit exceeded',
  }) : super(message);
}

/// The operation exceeded the configured timeout.
final class TimeoutFailure extends ChatFailure {
  const TimeoutFailure([super.message = 'Operation timed out']);
}

/// An unexpected error that doesn't fit other failure types. Check [originalError] for the root cause.
final class UnexpectedFailure extends ChatFailure {
  final Object? originalError;

  const UnexpectedFailure([
    super.message = 'Unexpected error',
    this.originalError,
  ]);
}

/// Avatar/image-storage backend failure (custom [AvatarStorage]
/// implementations or the default attachment-backed one). Keep
/// [cause] populated when possible so the host app can decide whether
/// to retry, log, or surface a localized error.
final class StorageFailure extends ChatFailure {
  final Object? cause;

  const StorageFailure([super.message = 'Storage error', this.cause]);
}
