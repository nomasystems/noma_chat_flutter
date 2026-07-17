import 'dart:async';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../cache/cache_manager.dart' show MetricCallback;
import 'auth_interceptor.dart';

/// Bearer token authentication with automatic refresh on 401 responses.
///
/// A simple circuit breaker guards the refresh-and-retry loop: each 401
/// that survives a token refresh increments a consecutive-failure counter
/// (metric `auth_refresh_retry_failure`). Once it reaches
/// [maxConsecutiveRefreshFailures], further 401s skip the refresh entirely
/// (metric `auth_circuit_open`) and go straight to [onAuthFailure], so a
/// revoked account cannot hammer the token endpoint. Any successful retry
/// or an explicit [invalidateCache] (new credentials) closes the circuit.
class BearerAuthInterceptor extends AuthInterceptor {
  final Future<String> Function() tokenProvider;
  final void Function()? onAuthFailure;
  final void Function(String level, String message)? logger;
  final MetricCallback? metricCallback;

  static const int maxConsecutiveRefreshFailures = 3;
  static const String _failureRecordedExtraKey = '_authFailureRecorded';

  Dio? _dio;
  String? _cachedToken;
  Completer<String>? _refreshCompleter;
  int _consecutiveRefreshFailures = 0;

  BearerAuthInterceptor({
    required this.tokenProvider,
    this.onAuthFailure,
    this.logger,
    this.metricCallback,
  });

  @visibleForTesting
  int get consecutiveRefreshFailures => _consecutiveRefreshFailures;

  void bindDio(Dio dio) => _dio = dio;

  @override
  void invalidateCache() {
    _cachedToken = null;
    _consecutiveRefreshFailures = 0;
  }

  @override
  Future<String> getAuthHeader() async {
    final token = _cachedToken ?? await _refreshToken();
    return 'Bearer $token';
  }

  Future<String> _refreshToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    final completer = Completer<String>();
    _refreshCompleter = completer;
    // Suppress "unhandled async error" if no concurrent caller listens to
    // the completer's future. The first caller propagates the error via the
    // `rethrow` below; concurrent callers that await `_refreshCompleter!.future`
    // still receive it through their own listeners.
    completer.future.then<void>((_) {}, onError: (_) {});
    try {
      final token = await tokenProvider();
      _cachedToken = token;
      completer.complete(token);
      return token;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    final options = err.requestOptions;
    if (options.extra['_authRetried'] == true) {
      _recordRefreshFailure(options);
      onAuthFailure?.call();
      return handler.next(err);
    }
    if (_consecutiveRefreshFailures >= maxConsecutiveRefreshFailures) {
      logger?.call(
        'warn',
        'auth.circuit: open after $_consecutiveRefreshFailures consecutive '
            'post-refresh 401s, skipping token refresh',
      );
      metricCallback?.call('auth_circuit_open', {
        'consecutiveFailures': _consecutiveRefreshFailures,
      });
      onAuthFailure?.call();
      return handler.next(err);
    }

    try {
      // Compare-and-invalidate. Only drop the cached token if it is still
      // the exact token this request sent: with several requests failing a
      // 401 in sequence, a later one whose 401 is handled after an earlier
      // refresh already cached a fresh token must NOT wipe it and trigger a
      // second tokenProvider() call (costly / rate-limited with Cognito).
      // If the cache already moved on, reuse the fresh token instead.
      final usedAuth = options.headers['Authorization'];
      final usedToken = usedAuth is String && usedAuth.startsWith('Bearer ')
          ? usedAuth.substring(7)
          : usedAuth is String
          ? usedAuth
          : null;
      final String newToken;
      if (usedToken != null &&
          _cachedToken != null &&
          _cachedToken != usedToken) {
        // The cache already moved past the token this request sent (a
        // concurrent 401 refreshed it): reuse the fresh one, don't refresh
        // again.
        newToken = _cachedToken!;
      } else {
        // Either we know the failed token is still the cached one, or the
        // request carried no recognizable token — invalidate (when it
        // matches) and refresh.
        if (_cachedToken == usedToken) _cachedToken = null;
        newToken = await _refreshToken();
      }
      options.headers['Authorization'] = 'Bearer $newToken';
      options.extra['_authRetried'] = true;

      final retryDio =
          _dio ??
          Dio(
            BaseOptions(
              baseUrl: options.baseUrl,
              connectTimeout: options.connectTimeout,
              receiveTimeout: options.receiveTimeout,
              sendTimeout: options.sendTimeout,
            ),
          );
      final response = await retryDio.fetch<dynamic>(options);
      _consecutiveRefreshFailures = 0;
      handler.resolve(response);
    } on DioException catch (retryErr) {
      if (retryErr.response?.statusCode == 401) {
        _recordRefreshFailure(retryErr.requestOptions);
        onAuthFailure?.call();
      }
      handler.next(retryErr);
    } catch (e) {
      logger?.call('warn', 'auth.retry: non-Dio error during retry: $e');
      onAuthFailure?.call();
      handler.next(err);
    }
  }

  /// Idempotent per request: when [_dio] is bound, the retried request runs
  /// the full interceptor chain, so its 401 reaches both the `_authRetried`
  /// branch and the retry `catch` with the same [RequestOptions] instance —
  /// the extra flag keeps that from double-counting one failure.
  void _recordRefreshFailure(RequestOptions options) {
    if (options.extra[_failureRecordedExtraKey] == true) return;
    options.extra[_failureRecordedExtraKey] = true;
    _consecutiveRefreshFailures++;
    metricCallback?.call('auth_refresh_retry_failure', {
      'consecutiveFailures': _consecutiveRefreshFailures,
    });
  }
}
