import 'dart:math';

import 'package:dio/dio.dart';

import 'circuit_breaker.dart';
import 'circuit_breaker_registry.dart';
import 'retry_config.dart';

class RetryInterceptor extends Interceptor {
  final RetryConfig _config;
  final Dio _dio;
  final CircuitBreaker? _circuitBreaker;
  final CircuitBreakerRegistry? _registry;
  final Random _random;

  RetryInterceptor({
    required RetryConfig config,
    required Dio dio,
    CircuitBreaker? circuitBreaker,
    CircuitBreakerRegistry? registry,
    Random? random,
  }) : _config = config,
       _dio = dio,
       _circuitBreaker = circuitBreaker,
       _registry = registry,
       _random = random ?? Random();

  CircuitBreaker? _breakerFor(RequestOptions options) =>
      _registry?.forPath(options.path) ?? _circuitBreaker;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_config.enabled) return handler.next(err);
    final breaker = _breakerFor(err.requestOptions);
    if (!_shouldRetry(err)) {
      breaker?.recordFailure();
      return handler.next(err);
    }

    final attempt = _getAttempt(err.requestOptions);
    if (attempt >= _config.maxRetries) {
      breaker?.recordFailure();
      return handler.next(err);
    }

    if (breaker != null && !breaker.allowRequest()) {
      return handler.next(err);
    }

    final delay = _calculateDelay(attempt, err.response);
    await Future<void>.delayed(delay);

    try {
      err.requestOptions.extra['_retryAttempt'] = attempt + 1;
      final response = await _dio.fetch<dynamic>(err.requestOptions);
      breaker?.recordSuccess();
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return onError(retryErr, handler);
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _breakerFor(response.requestOptions)?.recordSuccess();
    handler.next(response);
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = err.response?.statusCode;
    if (statusCode == null) return true;
    if (statusCode == 401 || statusCode == 403) return false;
    return _config.retryableStatusCodes.contains(statusCode);
  }

  int _getAttempt(RequestOptions options) =>
      (options.extra['_retryAttempt'] as int?) ?? 0;

  Duration _calculateDelay(int attempt, Response<dynamic>? response) {
    final retryAfter = _parseRetryAfter(response);
    if (retryAfter != null) return retryAfter;

    final exponentialMs =
        _config.baseDelay.inMilliseconds * pow(2, attempt).toInt();
    final jitterMs = _random.nextInt(500);
    final cappedMs = min(
      exponentialMs + jitterMs,
      _config.maxDelay.inMilliseconds,
    );
    return Duration(milliseconds: cappedMs);
  }

  Duration? _parseRetryAfter(Response<dynamic>? response) {
    if (response == null) return null;
    final header = response.headers.value('retry-after');
    if (header == null) return null;
    final seconds = int.tryParse(header);
    if (seconds != null) return Duration(seconds: seconds);
    return null;
  }
}
