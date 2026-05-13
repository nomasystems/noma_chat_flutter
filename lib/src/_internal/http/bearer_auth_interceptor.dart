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
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    final options = err.requestOptions;
    if (options.extra['_authRetried'] == true) {
      onAuthFailure?.call();
      return handler.next(err);
    }

    try {
      _cachedToken = null;
      final newToken = await _refreshToken();
      options.headers['Authorization'] = 'Bearer $newToken';
      options.extra['_authRetried'] = true;

      final retryDio = _dio ?? Dio(BaseOptions(
        baseUrl: options.baseUrl,
        connectTimeout: options.connectTimeout,
        receiveTimeout: options.receiveTimeout,
        sendTimeout: options.sendTimeout,
      ));
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
