/// Represents the outcome of an SDK operation: either [Success] with data or [Failure] with a [ChatFailure].
///
/// Use [fold] to handle both cases, or check [isSuccess]/[isFailure] and access
/// [dataOrNull]/[failureOrNull] directly.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get dataOrNull => switch (this) {
    Success(data: final d) => d,
    Failure() => null,
  };

  ChatFailure? get failureOrNull => switch (this) {
    Success() => null,
    Failure(failure: final f) => f,
  };

  R fold<R>(
    R Function(ChatFailure failure) onFailure,
    R Function(T data) onSuccess,
  ) => switch (this) {
    Success(data: final d) => onSuccess(d),
    Failure(failure: final f) => onFailure(f),
  };

  Result<R> map<R>(R Function(T data) transform) => switch (this) {
    Success(data: final d) => Success(transform(d)),
    Failure(failure: final f) => Failure(f),
  };

  Future<Result<R>> flatMap<R>(
    Future<Result<R>> Function(T data) transform,
  ) async => switch (this) {
    Success(data: final d) => await transform(d),
    Failure(failure: final f) => Failure(f),
  };
}

/// A successful result containing [data].
final class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Success<T> && other.data == data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Success($data)';
}

/// A failed result containing a [ChatFailure] describing what went wrong.
final class Failure<T> extends Result<T> {
  final ChatFailure failure;

  const Failure(this.failure);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Failure<T> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Failure($failure)';
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
