import '../../core/result.dart' show TimeoutKind;

sealed class ChatException implements Exception {
  final String message;

  /// Stable symbolic error token from the server's closed vocabulary
  /// (HTTP error body `error` field), or `null` when the response carried
  /// none. Threaded through `exception_mapper` onto the public
  /// `ChatFailure.errorToken` so host apps can branch/localize on a stable
  /// key. Subclasses that map a 1:1 typed condition (e.g.
  /// `ChatContentFilterException`) may leave this `null` and let the mapper
  /// supply the canonical token.
  final String? errorToken;

  const ChatException(this.message, {this.errorToken});

  @override
  String toString() => errorToken == null
      ? '$runtimeType: $message'
      : '$runtimeType($errorToken): $message';
}

final class ChatAuthException extends ChatException {
  /// `true` when the server refused authentication *terminally* — the
  /// cached credential is rejected and retrying (or failing over to a
  /// second transport) with it would only hammer the backend. Raised on
  /// WebSocket close code 4005 (`too_many_auth_attempts`). The realtime
  /// layer suspends every transport and the app must obtain a fresh
  /// token and reconnect explicitly. Ordinary (recoverable) auth errors
  /// keep [terminal] `false`.
  final bool terminal;

  // ignore: use_super_parameters
  const ChatAuthException([
    String message = 'Authentication failed',
    String? errorToken,
  ]) : terminal = false,
       super(message, errorToken: errorToken);

  const ChatAuthException.terminal([super.message = 'Authentication failed'])
    : terminal = true;
}

final class ChatForbiddenException extends ChatException {
  final int statusCode;
  final dynamic body;

  const ChatForbiddenException({
    this.statusCode = 403,
    this.body,
    String message = 'Forbidden',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

final class ChatNotFoundException extends ChatException {
  // ignore: use_super_parameters
  const ChatNotFoundException([
    String message = 'Not found',
    String? errorToken,
  ]) : super(message, errorToken: errorToken);
}

final class ChatValidationException extends ChatException {
  final Map<String, dynamic>? errors;

  const ChatValidationException({
    String message = 'Validation error',
    this.errors,
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

final class ChatContentFilterException extends ChatException {
  const ChatContentFilterException([
    super.message = 'Message blocked by content filter',
  ]);
}

final class ChatConflictException extends ChatException {
  // ignore: use_super_parameters
  const ChatConflictException([String message = 'Conflict', String? errorToken])
    : super(message, errorToken: errorToken);
}

final class ChatNetworkException extends ChatException {
  const ChatNetworkException([super.message = 'Network error']);
}

/// A deliberate abort — an `UploadCancelToken.cancel()` call, mapped from
/// the resulting Dio `DioExceptionType.cancel` — as opposed to a genuine
/// transport failure. `RestClient._mapDioException` only raises this for
/// its own upload-cancel sentinel reason, never for the bulk
/// `cancelPending`/`cancelPendingRequests` teardown paths, so a disconnect
/// or dispose mid-upload keeps mapping to the same failure it always has.
final class ChatCancelledException extends ChatException {
  const ChatCancelledException([super.message = 'Operation cancelled']);
}

final class ChatApiException extends ChatException {
  final int statusCode;
  final dynamic body;

  const ChatApiException({
    required this.statusCode,
    this.body,
    String message = 'API error',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

/// Server refused an upload for its size (413), mapped by
/// `RestClient._mapDioException` distinctly from the generic
/// [ChatApiException] so a caller can show the same "attachment too large"
/// message the client-side pre-flight rejection uses.
final class ChatAttachmentTooLargeException extends ChatException {
  final int statusCode;
  final dynamic body;

  const ChatAttachmentTooLargeException({
    this.statusCode = 413,
    this.body,
    String message = 'Attachment is too large',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

final class ChatRateLimitException extends ChatException {
  final Duration? retryAfter;

  const ChatRateLimitException({
    this.retryAfter,
    String message = 'Rate limit exceeded',
    String? errorToken,
  }) : super(message, errorToken: errorToken);
}

final class ChatTimeoutException extends ChatException {
  /// Which request phase timed out, so the offline queue / retry layer
  /// can tell a safe-to-resend pre-response timeout from a [receive]
  /// timeout that may already have reached the server.
  final TimeoutKind kind;

  const ChatTimeoutException({
    this.kind = TimeoutKind.unknown,
    String message = 'Operation timed out',
  }) : super(message);
}

final class ChatSseIdleTimeoutException extends ChatNetworkException {
  const ChatSseIdleTimeoutException([
    super.message = 'SSE stream idle (no chunks received)',
  ]);
}

final class ChatWsOperationException extends ChatException {
  final String? action;
  final String reason;

  const ChatWsOperationException({this.action, required this.reason})
    : super('WS error: ${action ?? "unknown"} - $reason');
}
