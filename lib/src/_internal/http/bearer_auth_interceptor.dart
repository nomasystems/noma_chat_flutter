import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_interceptor.dart';

/// Bearer token authentication with automatic refresh on 401 responses.
class BearerAuthInterceptor extends AuthInterceptor {
  final Future<String> Function() tokenProvider;
  final void Function()? onAuthFailure;
  final void Function(String level, String message)? logger;

  Dio? _dio;
  String? _cachedToken;
  Completer<String>? _refreshCompleter;

  BearerAuthInterceptor({
    required this.tokenProvider,
    this.onAuthFailure,
    this.logger,
  });

  void bindDio(Dio dio) => _dio = dio;

  @override
  void invalidateCache() {
    _cachedToken = null;
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
      handler.resolve(response);
    } on DioException catch (retryErr) {
      if (retryErr.response?.statusCode == 401) {
        onAuthFailure?.call();
      }
      handler.next(retryErr);
    } catch (e) {
      logger?.call('warn', 'auth.retry: non-Dio error during retry: $e');
      onAuthFailure?.call();
      handler.next(err);
    }
  }
}
