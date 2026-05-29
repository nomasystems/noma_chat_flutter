import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatResult accessors', () {
    test(
      'isSuccess/isFailure and dataOrNull/failureOrNull match ChatSuccess',
      () {
        const r = ChatSuccess<int>(7);
        expect(r.isSuccess, true);
        expect(r.isFailure, false);
        expect(r.dataOrNull, 7);
        expect(r.failureOrNull, isNull);
      },
    );

    test(
      'isSuccess/isFailure and dataOrNull/failureOrNull match ChatFailureResult',
      () {
        const r = ChatFailureResult<int>(NotFoundFailure());
        expect(r.isSuccess, false);
        expect(r.isFailure, true);
        expect(r.dataOrNull, isNull);
        expect(r.failureOrNull, isA<NotFoundFailure>());
      },
    );
  });

  group('ChatResult.fold', () {
    test('runs the success branch', () {
      final out = const ChatSuccess<int>(10).fold((f) => -1, (d) => d * 2);
      expect(out, 20);
    });

    test('runs the failure branch', () {
      final out = const ChatFailureResult<int>(
        NetworkFailure(),
      ).fold((f) => f.message, (d) => 'never');
      expect(out, contains('Network'));
    });
  });

  group('ChatResult.map', () {
    test('transforms ChatSuccess', () {
      final out = const ChatSuccess<int>(3).map((v) => 'v$v');
      expect(out, isA<ChatSuccess<String>>());
      expect(out.dataOrNull, 'v3');
    });

    test('keeps ChatFailureResult', () {
      final out = const ChatFailureResult<int>(
        NotFoundFailure(),
      ).map((v) => 'v$v');
      expect(out, isA<ChatFailureResult<String>>());
      expect(out.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('ChatResult.flatMap', () {
    test('chains on ChatSuccess', () async {
      final out = await const ChatSuccess<int>(
        2,
      ).flatMap<String>((v) async => ChatSuccess('v$v'));
      expect(out.dataOrNull, 'v2');
    });

    test('short-circuits on ChatFailureResult', () async {
      final out = await const ChatFailureResult<int>(
        NetworkFailure(),
      ).flatMap<String>((v) async => const ChatSuccess('reached'));
      expect(out.isFailure, true);
    });
  });

  group('Equality and toString', () {
    test('ChatSuccess equality + hashCode', () {
      const a = ChatSuccess<int>(7);
      const b = ChatSuccess<int>(7);
      const c = ChatSuccess<int>(8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), 'ChatSuccess(7)');
    });

    test('ChatFailureResult toString includes the failure type', () {
      const a = ChatFailureResult<int>(NotFoundFailure('nope'));
      expect(a.toString(), contains('NotFoundFailure'));
    });
  });

  group('ChatFailure subtypes', () {
    test('every subtype carries the expected message', () {
      expect(const AuthFailure().message, 'Authentication failed');
      expect(const NotFoundFailure().message, 'Not found');
      expect(const ValidationFailure().message, 'Validation failed');
      expect(
        const ContentFilterFailure().message,
        'Message blocked by content filter',
      );
      expect(const ConflictFailure().message, 'Conflict');
      expect(const NetworkFailure().message, 'Network error');
      expect(const ServerFailure(statusCode: 503).message, 'Server error');
      expect(const RateLimitFailure().message, 'Rate limit exceeded');
      expect(const TimeoutFailure().message, 'Operation timed out');
      expect(const UnexpectedFailure().message, 'Unexpected error');
      expect(const ForbiddenFailure().message, 'Forbidden');
    });

    test('toString includes the runtimeType', () {
      expect(
        const NetworkFailure().toString(),
        'NetworkFailure: Network error',
      );
    });

    test('ServerFailure carries statusCode + body', () {
      const f = ServerFailure(statusCode: 500, body: {'err': 'down'});
      expect(f.statusCode, 500);
      expect(f.body, {'err': 'down'});
    });

    test('RateLimitFailure carries retryAfter', () {
      const f = RateLimitFailure(retryAfter: Duration(seconds: 30));
      expect(f.retryAfter, const Duration(seconds: 30));
    });

    test('ValidationFailure carries errors map', () {
      const f = ValidationFailure(errors: {'email': 'invalid'});
      expect(f.errors, {'email': 'invalid'});
    });
  });
}
