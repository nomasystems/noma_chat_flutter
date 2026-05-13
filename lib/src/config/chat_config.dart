import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;

import '../_internal/http/auth_interceptor.dart';
import '../_internal/http/bearer_auth_interceptor.dart';
import '../_internal/http/basic_auth_interceptor.dart';
import '../_internal/cache/cache_config.dart';
import '../_internal/http/retry_config.dart';
import '../_internal/cache/local_datasource.dart';

/// Configuration for a [ChatClient] instance.
///
/// Requires [baseUrl] (REST API) and [realtimeUrl] (WebSocket/SSE). The default
/// constructor uses bearer token auth; use [ChatConfig.withBasicAuth] or
/// [ChatConfig.withAuthInterceptor] for other strategies.
class ChatConfig {
  final String baseUrl;
  final String realtimeUrl;
  final String? sseUrl;
  final String wsPath;
  final String ssePath;
  final String? userId;
  final AuthInterceptor authInterceptor;
  final Duration wsReconnectDelay;
  final Duration authTimeout;
  final Duration requestTimeout;
  final RetryConfig retryConfig;
  final CacheConfig? cacheConfig;
  final ChatLocalDatasource? localDatasource;
  final int? maxReconnectAttempts;
  final int eventBufferSize;
  final bool enableReconnectCatchUp;
  final void Function(String level, String message)? logger;

  String get effectiveSseUrl => sseUrl ?? realtimeUrl;

  /// Creates a config with bearer token authentication.
  ///
  /// [baseUrl] is the full REST base URL including API version (e.g. `http://host:8077/v1`).
  /// [realtimeUrl] is the HTTP base for WebSocket (scheme is converted to ws:// automatically).
  /// [tokenProvider] is called to obtain a fresh auth token on demand.
  ChatConfig({
    required this.baseUrl,
    required this.realtimeUrl,
    required Future<String> Function() tokenProvider,
    void Function()? onAuthFailure,
    this.sseUrl,
    this.wsPath = '/ws',
    this.ssePath = '/events',
    this.userId,
    this.wsReconnectDelay = const Duration(seconds: 2),
    this.authTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.retryConfig = const RetryConfig(),
    this.cacheConfig,
    this.localDatasource,
    this.maxReconnectAttempts,
    this.eventBufferSize = 0,
    this.enableReconnectCatchUp = false,
    this.logger,
  }) : authInterceptor = BearerAuthInterceptor(
          tokenProvider: tokenProvider,
          onAuthFailure: onAuthFailure,
          logger: logger,
        ) {
    _validate(baseUrl, realtimeUrl, sseUrl);
  }

  /// Creates a config with a custom [AuthInterceptor] for full control over authentication.
  ChatConfig.withAuthInterceptor({
    required this.baseUrl,
    required this.realtimeUrl,
    required this.authInterceptor,
    this.sseUrl,
    this.wsPath = '/ws',
    this.ssePath = '/events',
    this.userId,
    this.wsReconnectDelay = const Duration(seconds: 2),
    this.authTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.retryConfig = const RetryConfig(),
    this.cacheConfig,
    this.localDatasource,
    this.maxReconnectAttempts,
    this.eventBufferSize = 0,
    this.enableReconnectCatchUp = false,
    this.logger,
  }) {
    _validate(baseUrl, realtimeUrl, sseUrl);
  }

  /// Creates a config with HTTP Basic authentication.
  ChatConfig.withBasicAuth({
    required this.baseUrl,
    required this.realtimeUrl,
    required String username,
    required String password,
    this.sseUrl,
    this.wsPath = '/ws',
    this.ssePath = '/events',
    this.userId,
    this.wsReconnectDelay = const Duration(seconds: 2),
    this.authTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.retryConfig = const RetryConfig(),
    this.cacheConfig,
    this.localDatasource,
    this.maxReconnectAttempts,
    this.eventBufferSize = 0,
    this.enableReconnectCatchUp = false,
    this.logger,
  }) : authInterceptor =
            BasicAuthInterceptor(username: username, password: password) {
    _validate(baseUrl, realtimeUrl, sseUrl);
  }

  static void _validate(String baseUrl, String realtimeUrl, String? sseUrl) {
    validateUrls(
      baseUrl: baseUrl,
      realtimeUrl: realtimeUrl,
      sseUrl: sseUrl,
      isReleaseMode: kReleaseMode,
    );
  }

  /// Validates the URL set used by [ChatConfig].
  ///
  /// Public + parametric on [isReleaseMode] so tests can exercise the
  /// release-mode branch without rebuilding the binary. Production code
  /// always passes [kReleaseMode] (see [_validate]).
  @visibleForTesting
  static void validateUrls({
    required String baseUrl,
    required String realtimeUrl,
    String? sseUrl,
    required bool isReleaseMode,
  }) {
    final urls = <String, String>{
      'baseUrl': baseUrl,
      'realtimeUrl': realtimeUrl,
      if (sseUrl != null) 'sseUrl': sseUrl,
    };
    for (final entry in urls.entries) {
      final value = entry.value;
      final field = entry.key;

      if (value.endsWith('/')) {
        throw ArgumentError.value(
          value,
          field,
          'must not end with /. Example: "http://host:8077"',
        );
      }

      final scheme = Uri.parse(value).scheme;
      if (scheme == 'ws' || scheme == 'wss') {
        throw ArgumentError.value(
          value,
          field,
          'must use http or https scheme (transports convert automatically). '
              'Example: "http://host:8077"',
        );
      }

      if (scheme != 'http' && scheme != 'https') {
        throw ArgumentError.value(
          value,
          field,
          'must use http or https scheme.',
        );
      }

      // Plain http:// is allowed only during local development. Release builds
      // must always use https:// — chat traffic carries JWTs and message
      // bodies that we cannot afford to send in clear. See pentest M-10.
      if (scheme == 'http' && isReleaseMode) {
        throw ArgumentError.value(
          value,
          field,
          'http:// is not allowed in release builds; use https://.',
        );
      }
    }
  }

  void log(String level, String message) => logger?.call(level, message);
}
