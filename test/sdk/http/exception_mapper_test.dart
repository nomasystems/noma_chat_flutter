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
        const ChatForbiddenException(message: 'No access'),
      );
      expect(f, isA<ForbiddenFailure>());
      expect((f as ForbiddenFailure).message, 'No access');
    });

    test('maps ChatNotFoundException to NotFoundFailure', () {
      final f = mapExceptionToFailure(const ChatNotFoundException());
      expect(f, isA<NotFoundFailure>());
    });

    test('maps ChatValidationException to ValidationFailure', () {
      final f = mapExceptionToFailure(
        const ChatValidationException(
          message: 'Bad',
          errors: {'field': 'details'},
        ),
      );
      expect(f, isA<ValidationFailure>());
      expect((f as ValidationFailure).errors, {'field': 'details'});
    });

    test('maps ChatConflictException to ConflictFailure', () {
      final f = mapExceptionToFailure(const ChatConflictException());
      expect(f, isA<ConflictFailure>());
    });

    test('maps ChatRateLimitException to RateLimitFailure', () {
      final f = mapExceptionToFailure(
        const ChatRateLimitException(retryAfter: Duration(seconds: 10)),
      );
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
        const ChatApiException(statusCode: 502, message: 'Bad gateway'),
      );
      expect(f, isA<ServerFailure>());
      expect((f as ServerFailure).statusCode, 502);
    });

    test('ChatWsOperationException has action and reason', () {
      const e = ChatWsOperationException(
        action: 'message',
        reason: 'forbidden',
      );
      expect(e.action, 'message');
      expect(e.reason, 'forbidden');
      expect(e.message, contains('forbidden'));
      expect(e.message, contains('message'));
    });

    test('ChatWsOperationException maps to UnexpectedFailure', () {
      final f = mapExceptionToFailure(
        const ChatWsOperationException(reason: 'rate_limited'),
      );
      expect(f, isA<UnexpectedFailure>());
    });

    test('maps unknown exception to UnexpectedFailure', () {
      final f = mapExceptionToFailure(Exception('oops'));
      expect(f, isA<UnexpectedFailure>());
      expect((f as UnexpectedFailure).originalError, isA<Exception>());
    });
  });

  group('errorToken threading (A1)', () {
    test('threads the server token onto AuthFailure', () {
      final f = mapExceptionToFailure(
        const ChatAuthException('nope', ChatErrorTokens.accountBanned),
      );
      expect(f, isA<AuthFailure>());
      expect(f.errorToken, ChatErrorTokens.accountBanned);
    });

    test('threads the server token onto ForbiddenFailure', () {
      final f = mapExceptionToFailure(
        const ChatForbiddenException(
          errorToken: ChatErrorTokens.notARoomMember,
        ),
      );
      expect(f, isA<ForbiddenFailure>());
      expect(f.errorToken, ChatErrorTokens.notARoomMember);
    });

    test('routes the edit_window_expired token to its typed failure', () {
      final f = mapExceptionToFailure(
        const ChatForbiddenException(
          errorToken: ChatErrorTokens.editWindowExpired,
        ),
      );
      expect(f, isA<EditWindowExpiredFailure>());
      expect(f.errorToken, ChatErrorTokens.editWindowExpired);
    });

    test('routes the delete_window_expired token to its typed failure', () {
      final f = mapExceptionToFailure(
        const ChatForbiddenException(
          errorToken: ChatErrorTokens.deleteWindowExpired,
        ),
      );
      expect(f, isA<DeleteWindowExpiredFailure>());
      expect(f.errorToken, ChatErrorTokens.deleteWindowExpired);
    });

    test('falls back to the legacy detail string when the token is absent', () {
      final f = mapExceptionToFailure(
        const ChatForbiddenException(
          body: {'detail': ChatErrorTokens.editWindowExpired},
        ),
      );
      expect(f, isA<EditWindowExpiredFailure>());
    });

    test('threads the server token onto NotFoundFailure', () {
      final f = mapExceptionToFailure(
        const ChatNotFoundException('gone', ChatErrorTokens.roomNotFound),
      );
      expect(f, isA<NotFoundFailure>());
      expect(f.errorToken, ChatErrorTokens.roomNotFound);
    });

    test('threads the server token onto ServerFailure', () {
      final f = mapExceptionToFailure(
        const ChatApiException(statusCode: 500, errorToken: 'internal_oops'),
      );
      expect(f, isA<ServerFailure>());
      expect(f.errorToken, 'internal_oops');
    });

    test('defaults the rate-limit token when the server sends none', () {
      final f = mapExceptionToFailure(const ChatRateLimitException());
      expect(f, isA<RateLimitFailure>());
      expect(f.errorToken, ChatErrorTokens.rateLimited);
    });

    test('keeps an unknown token verbatim (open vocabulary)', () {
      final f = mapExceptionToFailure(
        const ChatConflictException('clash', 'brand_new_server_token'),
      );
      expect(f, isA<ConflictFailure>());
      expect(f.errorToken, 'brand_new_server_token');
    });

    test('errorToken is null when the server attached none', () {
      final f = mapExceptionToFailure(const ChatNotFoundException());
      expect(f.errorToken, isNull);
    });

    test('toString includes the token when present', () {
      final f = mapExceptionToFailure(
        const ChatConflictException('clash', 'already_member'),
      );
      expect(f.toString(), contains('already_member'));
    });
  });

  group('safeApiCall', () {
    test('returns ChatSuccess on success', () async {
      final result = await safeApiCall(() async => 42);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
    });

    test('returns ChatFailureResult on exception', () async {
      final result = await safeApiCall<int>(
        () async => throw const ChatAuthException(),
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });

  group('safeVoidCall', () {
    test('returns ChatSuccess on success', () async {
      final result = await safeVoidCall(() async {});
      expect(result.isSuccess, isTrue);
    });

    test('returns ChatFailureResult on exception', () async {
      final result = await safeVoidCall(
        () async => throw const ChatNetworkException(),
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });
}
