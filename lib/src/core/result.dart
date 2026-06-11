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

  /// Drops the success value, yielding a `ChatResult<void>` that preserves
  /// the success/failure outcome. Use when a richer API returns a value the
  /// caller doesn't need (e.g. a void-returning wrapper delegating to a
  /// value-returning method).
  ChatResult<void> discardValue() => switch (this) {
    ChatSuccess() => const ChatSuccess<void>(null),
    ChatFailureResult(failure: final f) => ChatFailureResult<void>(f),
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
///
/// Every failure carries a human-readable [message] (English, suitable for
/// logs) and, when the server provided one, a stable [errorToken]: a
/// snake_case symbolic code drawn from a server-owned, open-ended
/// vocabulary (e.g. `room_not_found`, `edit_window_expired`,
/// `cannot_delete_other_user`). Branch and localize on the token rather
/// than on the English prose, which is not contractual:
///
/// ```dart
/// result.fold(
///   (failure) {
///     final label = switch (failure.errorToken) {
///       ChatErrorTokens.editWindowExpired => l10n.editTooLate,
///       ChatErrorTokens.blocked => l10n.youAreBlocked,
///       ChatErrorTokens.rateLimited => l10n.slowDown,
///       _ => l10n.genericError, // unknown / older server / no token
///     };
///     showSnackBar(label);
///   },
///   (data) => render(data),
/// );
/// ```
///
/// [errorToken] is intentionally a `String?` rather than a closed enum so a
/// new server-side token never breaks the SDK or forces a release. It is
/// `null` when the server did not attach one (older servers, or responses
/// for which no token applies) — never the empty string.
sealed class ChatFailure {
  final String message;

  /// Stable symbolic error code from the server's closed vocabulary, or
  /// `null` when none was provided. See [ChatErrorTokens] for the
  /// well-known values the SDK itself reasons about; the full set is
  /// server-owned and may grow without an SDK change.
  final String? errorToken;

  const ChatFailure(this.message, {this.errorToken});

  @override
  String toString() => errorToken == null
      ? '$runtimeType: $message'
      : '$runtimeType($errorToken): $message';
}

/// Well-known stable error tokens the SDK reasons about. The server's
/// vocabulary is open-ended and larger than this set — these are only the
/// tokens with first-class SDK handling or that host apps commonly branch
/// on. Compare a [ChatFailure.errorToken] against these constants instead
/// of hard-coding string literals; unknown tokens still arrive verbatim on
/// [ChatFailure.errorToken].
abstract final class ChatErrorTokens {
  const ChatErrorTokens._();

  static const String roomNotFound = 'room_not_found';
  static const String notAMember = 'not_a_member';

  /// Caller is not a member of the room that owns the attachment. Surfaced by
  /// the attachment download / signed-URL endpoints, which enforce room
  /// membership fail-closed (a 403 with this token).
  static const String notARoomMember = 'not_a_room_member';
  static const String blocked = 'blocked';
  static const String banned = 'banned';
  static const String userMismatch = 'user_mismatch';
  static const String editWindowExpired = 'edit_window_expired';
  static const String deleteWindowExpired = 'delete_window_expired';
  static const String messageDeleted = 'message_deleted';
  static const String messageBlockedByContentFilter =
      'message_blocked_by_content_filter';
  static const String rateLimited = 'rate_limited';
  static const String cannotDeleteOtherUser = 'cannot_delete_other_user';

  /// Account-level deactivation/ban tokens that the SDK maps to
  /// [AuthFailure] so the host's re-auth flow fires.
  static const String userDeactivated = 'user_deactivated';
  static const String accountDeactivated = 'account_deactivated';
  static const String accountBanned = 'account_banned';
}

/// Authentication failed (401). Token may be expired or invalid.
final class AuthFailure extends ChatFailure {
  // `errorToken` is a second optional positional (not a super-param) because
  // `message` is already optional-positional and Dart forbids mixing
  // optional-positional with named in one signature; the base's `errorToken`
  // is named, so it is forwarded explicitly here.
  // ignore: use_super_parameters
  const AuthFailure([
    String message = 'Authentication failed',
    String? errorToken,
  ]) : super(message, errorToken: errorToken);
}

/// User lacks permission for the requested operation (403).
final class ForbiddenFailure extends ChatFailure {
  final int statusCode;
  final dynamic body;

  const ForbiddenFailure({
    this.statusCode = 403,
    this.body,
    String message = 'Forbidden',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

/// The edit window for a message has closed — the backend rejects the edit
/// with a 403 `edit_window_expired` (it allows edits only for a configured
/// time after a message is sent). The SDK also hides
/// [MessageAction.edit] past the window; this surfaces a late attempt that
/// slipped through (e.g. clock skew, a stale menu).
final class EditWindowExpiredFailure extends ChatFailure {
  // ignore: use_super_parameters
  const EditWindowExpiredFailure([String message = 'Edit window has expired'])
    : super(message, errorToken: ChatErrorTokens.editWindowExpired);
}

/// The "delete for everyone" window for a message has closed — the backend
/// rejects the delete with a 403 `delete_window_expired`.
final class DeleteWindowExpiredFailure extends ChatFailure {
  // ignore: use_super_parameters
  const DeleteWindowExpiredFailure([
    String message = 'Delete window has expired',
  ]) : super(message, errorToken: ChatErrorTokens.deleteWindowExpired);
}

/// Requested resource does not exist (404).
final class NotFoundFailure extends ChatFailure {
  // ignore: use_super_parameters
  const NotFoundFailure([String message = 'Not found', String? errorToken])
    : super(message, errorToken: errorToken);
}

/// Request parameters are invalid (400). Check [errors] for field-level details.
final class ValidationFailure extends ChatFailure {
  final Map<String, dynamic>? errors;

  const ValidationFailure({
    String message = 'Validation failed',
    this.errors,
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

/// Message blocked by a server-side content filter (400).
final class ContentFilterFailure extends ChatFailure {
  // ignore: use_super_parameters
  const ContentFilterFailure([
    String message = 'Message blocked by content filter',
  ]) : super(
         message,
         errorToken: ChatErrorTokens.messageBlockedByContentFilter,
       );
}

/// Resource already exists or conflicts with current state (409).
final class ConflictFailure extends ChatFailure {
  // ignore: use_super_parameters
  const ConflictFailure([String message = 'Conflict', String? errorToken])
    : super(message, errorToken: errorToken);
}

/// Network is unreachable or the connection was lost.
final class NetworkFailure extends ChatFailure {
  const NetworkFailure([super.message = 'Network error']);
}

/// Server returned a 5xx error (and the catch-all for unmapped HTTP status
/// codes). Carries the stable [errorToken] when the backend attached one.
final class ServerFailure extends ChatFailure {
  final int statusCode;
  final dynamic body;

  const ServerFailure({
    required this.statusCode,
    this.body,
    String message = 'Server error',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

/// Too many requests (429). Check [retryAfter] for the suggested wait time.
/// [errorToken] defaults to [ChatErrorTokens.rateLimited]; the server may
/// override it with a more specific token.
final class RateLimitFailure extends ChatFailure {
  final Duration? retryAfter;

  const RateLimitFailure({
    this.retryAfter,
    String message = 'Rate limit exceeded',
    String? errorToken = ChatErrorTokens.rateLimited,
  }) : super(message, errorToken: errorToken);
}

/// Which phase of a request timed out. Lets callers decide whether a
/// failed mutation is safe to retry: [connection] and [send] are
/// pre-response (the request never reached the server, so re-sending a
/// non-idempotent op is safe), whereas [receive] means the request was
/// already sent and the server may have processed it (re-sending risks a
/// duplicate). [unknown] is the defensive default when the phase is not
/// available.
enum TimeoutKind {
  connection,
  send,
  receive,
  unknown;

  /// True when the request provably never reached the server, so an
  /// automatic resend cannot create a duplicate.
  bool get isPreResponse =>
      this == TimeoutKind.connection || this == TimeoutKind.send;
}

/// The operation exceeded the configured timeout.
final class TimeoutFailure extends ChatFailure {
  final TimeoutKind kind;

  const TimeoutFailure({
    this.kind = TimeoutKind.unknown,
    String message = 'Operation timed out',
  }) : super(message);
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

/// Async ergonomics for `Future<ChatResult<T>>`, so transforms read left to
/// right without an intermediate `await` or `.then`.
extension ChatResultFutureX<T> on Future<ChatResult<T>> {
  /// Awaits and drops the success value to a `ChatResult<void>`, preserving
  /// the outcome. Mirror of [ChatResult.discardValue] for futures — lets a
  /// void-returning wrapper delegate to a value-returning method in one
  /// expression.
  Future<ChatResult<void>> discardValue() async => (await this).discardValue();
}
