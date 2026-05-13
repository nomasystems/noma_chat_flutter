import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/src/_internal/http/bearer_auth_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockDio extends Mock implements Dio {}

class _FakeRequestOptions extends Fake implements RequestOptions {}

RequestOptions _opts({Map<String, dynamic>? extra}) =>
    RequestOptions(path: '/test', extra: extra ?? {});

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRequestOptions());
  });

  group('BearerAuthInterceptor', () {
    test('adds Bearer token to request header', () async {
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async => 'token-abc',
      );

      final header = await interceptor.getAuthHeader();
      expect(header, 'Bearer token-abc');
    });

    test('caches token and reuses it', () async {
      var callCount = 0;
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          callCount++;
          return 'token-$callCount';
        },
      );

      final h1 = await interceptor.getAuthHeader();
      final h2 = await interceptor.getAuthHeader();

      expect(h1, 'Bearer token-1');
      expect(h2, 'Bearer token-1');
      expect(callCount, 1);
    });

    test('refreshes token on 401 and retries request', () async {
      var callCount = 0;
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          callCount++;
          return 'token-$callCount';
        },
      );

      await interceptor.getAuthHeader();
      expect(callCount, 1);

      final handler = _TrackingErrorHandler();
      final opts = _opts();
      opts.baseUrl = 'https://example.com';
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 401, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(callCount, 2);
    });

    test('serializes concurrent 401 refreshes', () async {
      var callCount = 0;
      final completer = Completer<String>();
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          callCount++;
          if (callCount == 1) return 'initial';
          return completer.future;
        },
      );

      await interceptor.getAuthHeader();
      callCount = 1;

      final handler1 = _TrackingErrorHandler();
      final handler2 = _TrackingErrorHandler();
      final opts1 = _opts();
      opts1.baseUrl = 'https://example.com';
      final opts2 = _opts();
      opts2.baseUrl = 'https://example.com';

      final err1 = DioException(
        requestOptions: opts1,
        response: Response(statusCode: 401, requestOptions: opts1),
      );
      final err2 = DioException(
        requestOptions: opts2,
        response: Response(statusCode: 401, requestOptions: opts2),
      );

      final f1 = interceptor.onError(err1, handler1);
      final f2 = interceptor.onError(err2, handler2);

      await Future<void>.delayed(Duration(milliseconds: 50));
      completer.complete('refreshed-token');
      await Future.wait([f1, f2]);

      expect(callCount, 2);
    });

    test('does not leak unhandled error when tokenProvider throws and no concurrent caller listens', () async {
      final unhandled = <Object>[];
      await runZonedGuarded(() async {
        final interceptor = BearerAuthInterceptor(
          tokenProvider: () async {
            throw StateError('token provider crashed');
          },
        );
        Object? thrownError;
        try {
          await interceptor.getAuthHeader();
        } catch (e) {
          thrownError = e;
        }
        expect(thrownError, isA<StateError>());
        // Allow microtasks to settle so any unhandled error would surface.
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => unhandled.add(e));
      expect(unhandled, isEmpty);
    });

    test('concurrent caller still receives the refresh error', () async {
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('token provider crashed');
        },
      );

      final f1 = interceptor.getAuthHeader();
      final f2 = interceptor.getAuthHeader();

      Object? err1;
      Object? err2;
      try {
        await f1;
      } catch (e) {
        err1 = e;
      }
      try {
        await f2;
      } catch (e) {
        err2 = e;
      }
      expect(err1, isA<StateError>());
      expect(err2, isA<StateError>());
    });

    test('calls onAuthFailure when retry also returns 401', () async {
      var authFailureCalled = false;
      var callCount = 0;
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          callCount++;
          return 'token-$callCount';
        },
        onAuthFailure: () => authFailureCalled = true,
      );

      await interceptor.getAuthHeader();

      final handler = _TrackingErrorHandler();
      final opts = _opts();
      opts.baseUrl = 'https://example.com';
      opts.extra['_authRetried'] = true;
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 401, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isTrue);
      expect(handler.nextCalled, isTrue);
    });

    test('does not call onAuthFailure on non-401 errors', () async {
      var authFailureCalled = false;
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async => 'token',
        onAuthFailure: () => authFailureCalled = true,
      );

      final handler = _TrackingErrorHandler();
      final opts = _opts();
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 500, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(handler.nextCalled, isTrue);
    });

    test('logs warning and triggers onAuthFailure on non-Dio retry error',
        () async {
      final logs = <String>[];
      var authFailureCalled = false;
      final mockDio = _MockDio();
      when(() => mockDio.fetch<dynamic>(any()))
          .thenThrow(StateError('retry boom'));

      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async => 'token',
        onAuthFailure: () => authFailureCalled = true,
        logger: (level, msg) => logs.add('$level: $msg'),
      );
      interceptor.bindDio(mockDio);

      final handler = _TrackingErrorHandler();
      final opts = _opts();
      opts.baseUrl = 'https://example.com';
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 401, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isTrue);
      expect(handler.nextCalled, isTrue);
      expect(logs, hasLength(1));
      expect(logs.first, startsWith('warn:'));
      expect(logs.first, contains('auth.retry'));
      expect(logs.first, contains('non-Dio error'));
      expect(logs.first, contains('retry boom'));
    });

    test('does not retry non-401 errors', () async {
      var callCount = 0;
      final interceptor = BearerAuthInterceptor(
        tokenProvider: () async {
          callCount++;
          return 'token-$callCount';
        },
      );

      await interceptor.getAuthHeader();

      final handler = _TrackingErrorHandler();
      final opts = _opts();
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 500, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(callCount, 1);
      expect(handler.nextCalled, isTrue);
    });
  });
}

class _TrackingErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? resolvedResponse;

  @override
  void next(DioException err) => nextCalled = true;

  @override
  void resolve(Response<dynamic> response) => resolvedResponse = response;
}
