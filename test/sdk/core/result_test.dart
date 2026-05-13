import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('Result accessors', () {
    test('isSuccess/isFailure and dataOrNull/failureOrNull match Success', () {
      const r = Success<int>(7);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);
      expect(r.dataOrNull, 7);
      expect(r.failureOrNull, isNull);
    });

    test('isSuccess/isFailure and dataOrNull/failureOrNull match Failure',
        () {
      const r = Failure<int>(NotFoundFailure());
      expect(r.isSuccess, false);
      expect(r.isFailure, true);
      expect(r.dataOrNull, isNull);
      expect(r.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('Result.fold', () {
    test('runs the success branch', () {
      final out = const Success<int>(10).fold((f) => -1, (d) => d * 2);
      expect(out, 20);
    });

    test('runs the failure branch', () {
      final out = const Failure<int>(NetworkFailure())
          .fold((f) => f.message, (d) => 'never');
      expect(out, contains('Network'));
    });
  });

  group('Result.map', () {
    test('transforms Success', () {
      final out = const Success<int>(3).map((v) => 'v$v');
      expect(out, isA<Success<String>>());
      expect(out.dataOrNull, 'v3');
    });

    test('keeps Failure', () {
      final out = const Failure<int>(NotFoundFailure()).map((v) => 'v$v');
      expect(out, isA<Failure<String>>());
      expect(out.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('Result.flatMap', () {
    test('chains on Success', () async {
      final out = await const Success<int>(2)
          .flatMap<String>((v) async => Success('v$v'));
      expect(out.dataOrNull, 'v2');
    });

    test('short-circuits on Failure', () async {
      final out = await const Failure<int>(NetworkFailure())
          .flatMap<String>((v) async => Success('reached'));
      expect(out.isFailure, true);
    });
  });

  group('Equality and toString', () {
    test('Success equality + hashCode', () {
      const a = Success<int>(7);
      const b = Success<int>(7);
      const c = Success<int>(8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), 'Success(7)');
    });

    test('Failure toString includes the failure type', () {
      const a = Failure<int>(NotFoundFailure('nope'));
      expect(a.toString(), contains('NotFoundFailure'));
    });
  });

  group('ChatFailure subtypes', () {
    test('every subtype carries the expected message', () {
      expect(const AuthFailure().message, 'Authentication failed');
      expect(const NotFoundFailure().message, 'Not found');
      expect(const ValidationFailure().message, 'Validation failed');
      expect(const ContentFilterFailure().message,
          'Message blocked by content filter');
      expect(const ConflictFailure().message, 'Conflict');
      expect(const NetworkFailure().message, 'Network error');
      expect(
          const ServerFailure(statusCode: 503).message, 'Server error');
      expect(const RateLimitFailure().message, 'Rate limit exceeded');
      expect(const TimeoutFailure().message, 'Operation timed out');
      expect(const UnexpectedFailure().message, 'Unexpected error');
      expect(const ForbiddenFailure().message, 'Forbidden');
    });

    test('toString includes the runtimeType', () {
      expect(const NetworkFailure().toString(),
          'NetworkFailure: Network error');
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
      const f =
          ValidationFailure(errors: {'email': 'invalid'});
      expect(f.errors, {'email': 'invalid'});
    });
  });
}
