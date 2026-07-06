import 'dart:math';

import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/src/_internal/http/circuit_breaker.dart';
import 'package:noma_chat/src/_internal/http/retry_config.dart';
import 'package:noma_chat/src/_internal/http/retry_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDio extends Mock implements Dio {}

/// Captures the outcome of an `onRequest` call without completing the real
/// dio future (the unit test only inspects which branch was taken).
class _TrackingRequestHandler extends RequestInterceptorHandler {
  DioException? rejectedError;
  RequestOptions? nextOptions;

  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {
    rejectedError = error;
  }

  @override
  void next(RequestOptions requestOptions) {
    nextOptions = requestOptions;
  }
}

RequestOptions _opts({Map<String, dynamic>? extra}) =>
    RequestOptions(path: '/test', extra: extra ?? {});

void main() {
  late MockDio dio;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    dio = MockDio();
  });

  group('RetryInterceptor', () {
    test('does not retry 401 errors', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 1),
        ),
        dio: dio,
      );

      final handler = _TrackingErrorHandler();
      final err = DioException(
        requestOptions: _opts(),
        response: Response(statusCode: 401, requestOptions: _opts()),
      );

      await interceptor.onError(err, handler);

      expect(handler.nextCalled, isTrue);
      verifyNever(() => dio.fetch<dynamic>(any()));
    });

    test('onRequest fast-fails when the circuit is open', () {
      final breaker = CircuitBreaker(failureThreshold: 1);
      breaker.recordFailure(); // opens the circuit (threshold = 1)
      final interceptor = RetryInterceptor(
        config: const RetryConfig(maxRetries: 3),
        dio: dio,
        circuitBreaker: breaker,
      );

      final handler = _TrackingRequestHandler();
      interceptor.onRequest(_opts(), handler);

      expect(handler.rejectedError, isNotNull);
      expect(handler.rejectedError!.type, DioExceptionType.connectionError);
      expect(handler.nextOptions, isNull);
    });

    test('onRequest lets the request through when the circuit is closed', () {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(maxRetries: 3),
        dio: dio,
        circuitBreaker: CircuitBreaker(failureThreshold: 5),
      );

      final handler = _TrackingRequestHandler();
      interceptor.onRequest(_opts(), handler);

      expect(handler.nextOptions, isNotNull);
      expect(handler.rejectedError, isNull);
    });

    test('does not retry 403 errors', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 1),
        ),
        dio: dio,
      );

      final handler = _TrackingErrorHandler();
      final err = DioException(
        requestOptions: _opts(),
        response: Response(statusCode: 403, requestOptions: _opts()),
      );

      await interceptor.onError(err, handler);

      expect(handler.nextCalled, isTrue);
      verifyNever(() => dio.fetch<dynamic>(any()));
    });

    test('retries 429 errors', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 1,
          baseDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 10),
        ),
        dio: dio,
        random: _FixedRandom(),
      );

      final opts = _opts();
      final successResponse = Response(
        statusCode: 200,
        requestOptions: opts,
        data: {'ok': true},
      );

      when(
        () => dio.fetch<dynamic>(any()),
      ).thenAnswer((_) async => successResponse);

      final handler = _TrackingErrorHandler();
      final err = DioException(
        requestOptions: opts,
        response: Response(statusCode: 429, requestOptions: opts),
      );

      await interceptor.onError(err, handler);

      expect(handler.resolvedResponse, isNotNull);
      verify(() => dio.fetch<dynamic>(any())).called(1);
    });

    test('retries 502/503/504 errors', () async {
      for (final code in [502, 503, 504]) {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 1,
            baseDelay: Duration(milliseconds: 1),
            maxDelay: Duration(milliseconds: 10),
          ),
          dio: dio,
          random: _FixedRandom(),
        );

        final opts = _opts();
        when(() => dio.fetch<dynamic>(any())).thenAnswer(
          (_) async => Response(statusCode: 200, requestOptions: opts),
        );

        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            response: Response(statusCode: code, requestOptions: opts),
          ),
          handler,
        );

        expect(
          handler.resolvedResponse,
          isNotNull,
          reason: 'Should retry $code',
        );
        reset(dio);
      }
    });

    test('respects Retry-After header', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 1,
          baseDelay: Duration(milliseconds: 1),
        ),
        dio: dio,
        random: _FixedRandom(),
      );

      final opts = _opts();
      final response429 = Response(
        statusCode: 429,
        requestOptions: opts,
        headers: Headers.fromMap({
          'retry-after': ['1'],
        }),
      );

      when(() => dio.fetch<dynamic>(any())).thenAnswer(
        (_) async => Response(statusCode: 200, requestOptions: opts),
      );

      final handler = _TrackingErrorHandler();
      final start = DateTime.now();
      await interceptor.onError(
        DioException(requestOptions: opts, response: response429),
        handler,
      );
      final elapsed = DateTime.now().difference(start);

      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(900));
      expect(handler.resolvedResponse, isNotNull);
    });

    test('clamps a zero/negative Retry-After up to the 1s minimum '
        '(no retry stampede on clock skew)', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 1,
          baseDelay: Duration(milliseconds: 1),
        ),
        dio: dio,
        random: _FixedRandom(),
      );

      final opts = _opts();
      // Clock skew can produce a 0 (or negative) reset. The clamp must floor
      // it at 1s instead of retrying immediately.
      final response429 = Response(
        statusCode: 429,
        requestOptions: opts,
        headers: Headers.fromMap({
          'x-ratelimit-reset': ['0'],
        }),
      );

      when(() => dio.fetch<dynamic>(any())).thenAnswer(
        (_) async => Response(statusCode: 200, requestOptions: opts),
      );

      final handler = _TrackingErrorHandler();
      final start = DateTime.now();
      await interceptor.onError(
        DioException(requestOptions: opts, response: response429),
        handler,
      );
      final elapsed = DateTime.now().difference(start);

      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(900));
      expect(handler.resolvedResponse, isNotNull);
    });

    test('falls back to X-RateLimit-Reset when no Retry-After', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 1,
          baseDelay: Duration(milliseconds: 1),
        ),
        dio: dio,
        random: _FixedRandom(),
      );

      final opts = _opts();
      final response429 = Response(
        statusCode: 429,
        requestOptions: opts,
        headers: Headers.fromMap({
          'x-ratelimit-reset': ['1'],
        }),
      );

      when(() => dio.fetch<dynamic>(any())).thenAnswer(
        (_) async => Response(statusCode: 200, requestOptions: opts),
      );

      final handler = _TrackingErrorHandler();
      final start = DateTime.now();
      await interceptor.onError(
        DioException(requestOptions: opts, response: response429),
        handler,
      );
      final elapsed = DateTime.now().difference(start);

      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(900));
      expect(handler.resolvedResponse, isNotNull);
    });

    test('stops after maxRetries exceeded', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 2,
          baseDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 10),
        ),
        dio: dio,
        random: _FixedRandom(),
      );

      final opts = _opts(extra: {'_retryAttempt': 2});
      final handler = _TrackingErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: opts,
          response: Response(statusCode: 503, requestOptions: opts),
        ),
        handler,
      );

      expect(handler.nextCalled, isTrue);
      verifyNever(() => dio.fetch<dynamic>(any()));
    });

    test('records success to circuit breaker on response', () {
      final cb = CircuitBreaker(failureThreshold: 5);
      final interceptor = RetryInterceptor(
        config: const RetryConfig(),
        dio: dio,
        circuitBreaker: cb,
      );

      final handler = _TrackingResponseHandler();
      interceptor.onResponse(
        Response(statusCode: 200, requestOptions: _opts()),
        handler,
      );

      expect(handler.nextCalled, isTrue);
    });

    test('disabled config skips retry', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig.disabled(),
        dio: dio,
      );

      final handler = _TrackingErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: _opts(),
          response: Response(statusCode: 503, requestOptions: _opts()),
        ),
        handler,
      );

      expect(handler.nextCalled, isTrue);
      verifyNever(() => dio.fetch<dynamic>(any()));
    });

    group('idempotency', () {
      test('POST with connectionError is NOT retried (safe default)', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 3,
            baseDelay: Duration(milliseconds: 1),
          ),
          dio: dio,
        );

        final opts = RequestOptions(path: '/test', method: 'POST');
        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
          ),
          handler,
        );

        expect(handler.nextCalled, isTrue);
        verifyNever(() => dio.fetch<dynamic>(any()));
      });

      test('POST with sendTimeout is NOT retried', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 3,
            baseDelay: Duration(milliseconds: 1),
          ),
          dio: dio,
        );

        final opts = RequestOptions(path: '/test', method: 'POST');
        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.sendTimeout,
          ),
          handler,
        );

        expect(handler.nextCalled, isTrue);
        verifyNever(() => dio.fetch<dynamic>(any()));
      });

      test('POST with connectionTimeout is NOT retried', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 3,
            baseDelay: Duration(milliseconds: 1),
          ),
          dio: dio,
        );

        final opts = RequestOptions(path: '/test', method: 'POST');
        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionTimeout,
          ),
          handler,
        );

        expect(handler.nextCalled, isTrue);
        verifyNever(() => dio.fetch<dynamic>(any()));
      });

      test('PATCH with connectionError is NOT retried', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 3,
            baseDelay: Duration(milliseconds: 1),
          ),
          dio: dio,
        );

        final opts = RequestOptions(path: '/test', method: 'PATCH');
        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
          ),
          handler,
        );

        expect(handler.nextCalled, isTrue);
        verifyNever(() => dio.fetch<dynamic>(any()));
      });

      test(
        'POST with receiveTimeout IS retried (request reached the server)',
        () async {
          final interceptor = RetryInterceptor(
            config: const RetryConfig(
              maxRetries: 1,
              baseDelay: Duration(milliseconds: 1),
              maxDelay: Duration(milliseconds: 5),
            ),
            dio: dio,
            random: _FixedRandom(),
          );

          final opts = RequestOptions(path: '/test', method: 'POST');
          when(() => dio.fetch<dynamic>(any())).thenAnswer(
            (_) async => Response(statusCode: 200, requestOptions: opts),
          );

          final handler = _TrackingErrorHandler();
          await interceptor.onError(
            DioException(
              requestOptions: opts,
              type: DioExceptionType.receiveTimeout,
            ),
            handler,
          );

          expect(handler.resolvedResponse, isNotNull);
          verify(() => dio.fetch<dynamic>(any())).called(1);
        },
      );

      test(
        'POST with extra[idempotent]=true IS retried on connectionError',
        () async {
          final interceptor = RetryInterceptor(
            config: const RetryConfig(
              maxRetries: 1,
              baseDelay: Duration(milliseconds: 1),
              maxDelay: Duration(milliseconds: 5),
            ),
            dio: dio,
            random: _FixedRandom(),
          );

          final opts = RequestOptions(
            path: '/test',
            method: 'POST',
            extra: {'idempotent': true},
          );
          when(() => dio.fetch<dynamic>(any())).thenAnswer(
            (_) async => Response(statusCode: 200, requestOptions: opts),
          );

          final handler = _TrackingErrorHandler();
          await interceptor.onError(
            DioException(
              requestOptions: opts,
              type: DioExceptionType.connectionError,
            ),
            handler,
          );

          expect(handler.resolvedResponse, isNotNull);
          verify(() => dio.fetch<dynamic>(any())).called(1);
        },
      );

      test('GET with connectionError IS retried (idempotent)', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 1,
            baseDelay: Duration(milliseconds: 1),
            maxDelay: Duration(milliseconds: 5),
          ),
          dio: dio,
          random: _FixedRandom(),
        );

        final opts = RequestOptions(path: '/test', method: 'GET');
        when(() => dio.fetch<dynamic>(any())).thenAnswer(
          (_) async => Response(statusCode: 200, requestOptions: opts),
        );

        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
          ),
          handler,
        );

        expect(handler.resolvedResponse, isNotNull);
        verify(() => dio.fetch<dynamic>(any())).called(1);
      });

      test('PUT with connectionError IS retried (idempotent)', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 1,
            baseDelay: Duration(milliseconds: 1),
            maxDelay: Duration(milliseconds: 5),
          ),
          dio: dio,
          random: _FixedRandom(),
        );

        final opts = RequestOptions(path: '/test', method: 'PUT');
        when(() => dio.fetch<dynamic>(any())).thenAnswer(
          (_) async => Response(statusCode: 200, requestOptions: opts),
        );

        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
          ),
          handler,
        );

        expect(handler.resolvedResponse, isNotNull);
        verify(() => dio.fetch<dynamic>(any())).called(1);
      });

      test('DELETE with connectionError IS retried (idempotent)', () async {
        final interceptor = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 1,
            baseDelay: Duration(milliseconds: 1),
            maxDelay: Duration(milliseconds: 5),
          ),
          dio: dio,
          random: _FixedRandom(),
        );

        final opts = RequestOptions(path: '/test', method: 'DELETE');
        when(() => dio.fetch<dynamic>(any())).thenAnswer(
          (_) async => Response(statusCode: 200, requestOptions: opts),
        );

        final handler = _TrackingErrorHandler();
        await interceptor.onError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
          ),
          handler,
        );

        expect(handler.resolvedResponse, isNotNull);
        verify(() => dio.fetch<dynamic>(any())).called(1);
      });

      test(
        'POST with 503 IS retried (server-side error, not pre-response)',
        () async {
          final interceptor = RetryInterceptor(
            config: const RetryConfig(
              maxRetries: 1,
              baseDelay: Duration(milliseconds: 1),
              maxDelay: Duration(milliseconds: 5),
            ),
            dio: dio,
            random: _FixedRandom(),
          );

          final opts = RequestOptions(path: '/test', method: 'POST');
          when(() => dio.fetch<dynamic>(any())).thenAnswer(
            (_) async => Response(statusCode: 200, requestOptions: opts),
          );

          final handler = _TrackingErrorHandler();
          await interceptor.onError(
            DioException(
              requestOptions: opts,
              response: Response(statusCode: 503, requestOptions: opts),
            ),
            handler,
          );

          expect(handler.resolvedResponse, isNotNull);
          verify(() => dio.fetch<dynamic>(any())).called(1);
        },
      );
    });
  });
}

class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0.0;
  @override
  bool nextBool() => false;
}

class _TrackingErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? resolvedResponse;

  @override
  void next(DioException err) => nextCalled = true;

  @override
  void resolve(Response<dynamic> response) => resolvedResponse = response;
}

class _TrackingResponseHandler extends ResponseInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(Response<dynamic> response) => nextCalled = true;
}
