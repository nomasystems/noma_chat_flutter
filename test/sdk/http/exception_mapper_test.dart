import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/exception_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapExceptionToFailure', () {
    test('maps ChatAuthException to AuthFailure', () {
      final f = mapExceptionToFailure(const ChatAuthException());
      expect(f, isA<AuthFailure>());
    });

    test('maps ChatForbiddenException to ForbiddenFailure', () {
      final f = mapExceptionToFailure(
          const ChatForbiddenException(message: 'No access'));
      expect(f, isA<ForbiddenFailure>());
      expect((f as ForbiddenFailure).message, 'No access');
    });

    test('maps ChatNotFoundException to NotFoundFailure', () {
      final f = mapExceptionToFailure(const ChatNotFoundException());
      expect(f, isA<NotFoundFailure>());
    });

    test('maps ChatValidationException to ValidationFailure', () {
      final f = mapExceptionToFailure(
          const ChatValidationException(message: 'Bad', errors: {'field': 'details'}));
      expect(f, isA<ValidationFailure>());
      expect((f as ValidationFailure).errors, {'field': 'details'});
    });

    test('maps ChatConflictException to ConflictFailure', () {
      final f = mapExceptionToFailure(const ChatConflictException());
      expect(f, isA<ConflictFailure>());
    });

    test('maps ChatRateLimitException to RateLimitFailure', () {
      final f = mapExceptionToFailure(
          const ChatRateLimitException(retryAfter: Duration(seconds: 10)));
      expect(f, isA<RateLimitFailure>());
      expect((f as RateLimitFailure).retryAfter, const Duration(seconds: 10));
    });

    test('maps ChatNetworkException to NetworkFailure', () {
      final f = mapExceptionToFailure(const ChatNetworkException());
      expect(f, isA<NetworkFailure>());
    });

    test('maps ChatTimeoutException to TimeoutFailure', () {
      final f = mapExceptionToFailure(const ChatTimeoutException());
      expect(f, isA<TimeoutFailure>());
    });

    test('maps ChatApiException to ServerFailure', () {
      final f = mapExceptionToFailure(
          const ChatApiException(statusCode: 502, message: 'Bad gateway'));
      expect(f, isA<ServerFailure>());
      expect((f as ServerFailure).statusCode, 502);
    });

    test('ChatWsOperationException has action and reason', () {
      const e = ChatWsOperationException(action: 'message', reason: 'forbidden');
      expect(e.action, 'message');
      expect(e.reason, 'forbidden');
      expect(e.message, contains('forbidden'));
      expect(e.message, contains('message'));
    });

    test('ChatWsOperationException maps to UnexpectedFailure', () {
      final f = mapExceptionToFailure(
          const ChatWsOperationException(reason: 'rate_limited'));
      expect(f, isA<UnexpectedFailure>());
    });

    test('maps unknown exception to UnexpectedFailure', () {
      final f = mapExceptionToFailure(Exception('oops'));
      expect(f, isA<UnexpectedFailure>());
      expect((f as UnexpectedFailure).originalError, isA<Exception>());
    });
  });

  group('safeApiCall', () {
    test('returns Success on success', () async {
      final result = await safeApiCall(() async => 42);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
    });

    test('returns Failure on exception', () async {
      final result = await safeApiCall<int>(
          () async => throw const ChatAuthException());
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });

  group('safeVoidCall', () {
    test('returns Success on success', () async {
      final result = await safeVoidCall(() async {});
      expect(result.isSuccess, isTrue);
    });

    test('returns Failure on exception', () async {
      final result =
          await safeVoidCall(() async => throw const ChatNetworkException());
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });
}
