sealed class ChatException implements Exception {
  final String message;

  const ChatException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

final class ChatAuthException extends ChatException {
  const ChatAuthException([super.message = 'Authentication failed']);
}

final class ChatForbiddenException extends ChatException {
  final int statusCode;
  final dynamic body;

  const ChatForbiddenException({
    this.statusCode = 403,
    this.body,
    String message = 'Forbidden',
  }) : super(message);
}

final class ChatNotFoundException extends ChatException {
  const ChatNotFoundException([super.message = 'Not found']);
}

final class ChatValidationException extends ChatException {
  final Map<String, dynamic>? errors;

  const ChatValidationException({
    String message = 'Validation error',
    this.errors,
  }) : super(message);
}

final class ChatContentFilterException extends ChatException {
  const ChatContentFilterException([
    super.message = 'Message blocked by content filter',
  ]);
}

final class ChatConflictException extends ChatException {
  const ChatConflictException([super.message = 'Conflict']);
}

final class ChatNetworkException extends ChatException {
  const ChatNetworkException([super.message = 'Network error']);
}

final class ChatApiException extends ChatException {
  final int statusCode;
  final dynamic body;

  const ChatApiException({
    required this.statusCode,
    this.body,
    String message = 'API error',
  }) : super(message);
}

final class ChatRateLimitException extends ChatException {
  final Duration? retryAfter;

  const ChatRateLimitException({
    this.retryAfter,
    String message = 'Rate limit exceeded',
  }) : super(message);
}

final class ChatTimeoutException extends ChatException {
  const ChatTimeoutException([super.message = 'Operation timed out']);
}

final class ChatWsOperationException extends ChatException {
  final String? action;
  final String reason;

  const ChatWsOperationException({this.action, required this.reason})
    : super('WS error: ${action ?? "unknown"} - $reason');
}
