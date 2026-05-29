import '../../core/result.dart';
import 'chat_exception.dart';

ChatFailure mapExceptionToFailure(Object e) {
  if (e is ChatAuthException) return const AuthFailure();
  if (e is ChatForbiddenException) {
    return ForbiddenFailure(
      statusCode: e.statusCode,
      body: e.body,
      message: e.message,
    );
  }
  if (e is ChatNotFoundException) return NotFoundFailure(e.message);
  if (e is ChatContentFilterException) {
    return ContentFilterFailure(e.message);
  }
  if (e is ChatValidationException) {
    return ValidationFailure(message: e.message, errors: e.errors);
  }
  if (e is ChatConflictException) return ConflictFailure(e.message);
  if (e is ChatRateLimitException) {
    return RateLimitFailure(retryAfter: e.retryAfter);
  }
  if (e is ChatNetworkException) return NetworkFailure(e.message);
  if (e is ChatTimeoutException) return const TimeoutFailure();
  if (e is ChatApiException) {
    return ServerFailure(
      statusCode: e.statusCode,
      body: e.body,
      message: e.message,
    );
  }
  return UnexpectedFailure(e.toString(), e);
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
