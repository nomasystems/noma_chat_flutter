import '../../core/result.dart';
import 'chat_exception.dart';

ChatFailure mapExceptionToFailure(Object e) {
  if (e is ChatAuthException) {
    return AuthFailure('Authentication failed', e.errorToken);
  }
  if (e is ChatForbiddenException) {
    // Token-first routing: the stable server token wins over the legacy
    // `detail` string match (which is kept as a fallback for servers that
    // don't yet emit the token). Either path lands on the same typed
    // failure, and both carry the token onward via `errorToken`.
    final token = e.errorToken;
    final detail = _forbiddenDetail(e);
    if (token == ChatErrorTokens.editWindowExpired ||
        detail == ChatErrorTokens.editWindowExpired) {
      return const EditWindowExpiredFailure();
    }
    if (token == ChatErrorTokens.deleteWindowExpired ||
        detail == ChatErrorTokens.deleteWindowExpired) {
      return const DeleteWindowExpiredFailure();
    }
    return ForbiddenFailure(
      statusCode: e.statusCode,
      body: e.body,
      message: e.message,
      errorToken: token,
    );
  }
  if (e is ChatNotFoundException) {
    return NotFoundFailure(e.message, e.errorToken);
  }
  if (e is ChatContentFilterException) {
    return ContentFilterFailure(e.message);
  }
  if (e is ChatValidationException) {
    return ValidationFailure(
      message: e.message,
      errors: e.errors,
      errorToken: e.errorToken,
    );
  }
  if (e is ChatConflictException) {
    return ConflictFailure(e.message, e.errorToken);
  }
  if (e is ChatRateLimitException) {
    return RateLimitFailure(
      retryAfter: e.retryAfter,
      // Default the token to `rate_limited` when the server didn't tag a
      // more specific one (e.g. older servers on a 429).
      errorToken: e.errorToken ?? ChatErrorTokens.rateLimited,
    );
  }
  if (e is ChatNetworkException) return NetworkFailure(e.message);
  if (e is ChatTimeoutException) return TimeoutFailure(kind: e.kind);
  if (e is ChatApiException) {
    return ServerFailure(
      statusCode: e.statusCode,
      body: e.body,
      message: e.message,
      errorToken: e.errorToken,
    );
  }
  return UnexpectedFailure(e.toString(), e);
}

/// Extracts the backend's `detail` code from a 403 so the mapper can route
/// edit/delete-window rejections to their typed failures when the server
/// did not emit a stable `error` token. The detail lives in the response
/// body (`ChatForbiddenException.message` only carries the transport-level
/// text).
String? _forbiddenDetail(ChatForbiddenException e) {
  final body = e.body;
  if (body is Map && body['detail'] is String) {
    return (body['detail'] as String).trim();
  }
  return null;
}

Future<ChatResult<T>> safeApiCall<T>(Future<T> Function() call) async {
  try {
    return ChatSuccess(await call());
  } catch (e) {
    return ChatFailureResult(mapExceptionToFailure(e));
  }
}

Future<ChatResult<void>> safeVoidCall(Future<void> Function() call) async {
  try {
    await call();
    return const ChatSuccess(null);
  } catch (e) {
    return ChatFailureResult(mapExceptionToFailure(e));
  }
}
