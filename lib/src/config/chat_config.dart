import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show kDebugMode, kReleaseMode, visibleForTesting;
import 'package:meta/meta.dart' show experimental;

import '../_internal/cache/cache_manager.dart' show MetricCallback;
import '../_internal/http/auth_interceptor.dart';
import '../_internal/http/bearer_auth_interceptor.dart';
import '../_internal/http/basic_auth_interceptor.dart';
import '../_internal/cache/cache_config.dart';
import '../_internal/http/retry_config.dart';
import '../cache/local_datasource.dart';
import 'polling_config.dart';
import 'realtime_mode.dart';

export 'polling_config.dart';
export 'realtime_mode.dart';

/// Configuration for a [ChatClient] instance.
///
/// Requires [baseUrl] (REST API) and [realtimeUrl] (WebSocket/SSE). The default
/// constructor uses bearer token auth; use [ChatConfig.withBasicAuth] or
/// [ChatConfig.withAuthInterceptor] for other strategies.
///
/// All three public constructors delegate to a private one ([ChatConfig._])
/// so the 17 transport / cache / observability params don't have to be
/// declared three times.
class ChatConfig {
  final String baseUrl;
  final String realtimeUrl;
  final String? sseUrl;
  final String wsPath;
  final String ssePath;
  final String? userId;

  /// Called when authentication fails terminally and the host app should
  /// route the user to a logout / login flow. Wired into the auth
  /// interceptor for the REST path (401 after refresh, or a 403
  /// deactivation body) and also held here so the realtime client can
  /// invoke it when the WebSocket delivers a deactivation / account-banned
  /// signal (close code 4007 or an `account_deactivated` auth error) — a
  /// path the REST interceptor never sees because an idle socket makes no
  /// HTTP call. `null` when the host opted out of automatic logout.
  final void Function()? onAuthFailure;

  /// When set, every request injects `X-From-User-Id: <actAsUserId>` so the
  /// SDK acts on behalf of a managed user (delegation). The backend enforces
  /// the parent→managed relationship and responds 403 if it is not allowed.
  final String? actAsUserId;
  final AuthInterceptor authInterceptor;
  final Duration wsReconnectDelay;
  final Duration authTimeout;
  final Duration requestTimeout;

  /// Maximum interval between SSE chunks before the client assumes the
  /// stream went silent (NAT/proxy timeout, dead backend) and forces a
  /// reconnect. WS has built-in 30 s pings; SSE relies on chunk traffic.
  /// Defaults to 60 s. Pass `null` to disable the watchdog. The backend
  /// (NRTE) is expected to emit `:` comments below this interval as a
  /// keep-alive; if it doesn't, the watchdog will reconnect periodically
  /// on idle rooms — still correct, just more chatty.
  final Duration? sseIdleTimeout;

  /// Which real-time transport strategy to use. Defaults to
  /// [RealtimeMode.auto] (WS primary + SSE fallback).
  final RealtimeMode realtimeMode;

  /// Tunables for [RealtimeMode.polling]. Ignored in other modes.
  /// When polling is selected without an explicit instance,
  /// `PollingConfig()` defaults apply.
  final PollingConfig? pollingConfig;

  final RetryConfig retryConfig;
  final CacheConfig? cacheConfig;
  final ChatLocalDatasource? localDatasource;
  final int? maxReconnectAttempts;
  final int eventBufferSize;
  final bool enableReconnectCatchUp;
  final void Function(String level, String message)? logger;

  /// When `true` AND [logger] is non-null, [RestClient] attaches a dio
  /// interceptor that emits one `http.req`/`http.res`/`http.err` line
  /// per request. Bodies are truncated to 512 chars. Defaults to
  /// `false` so production apps that wire a generic [logger] don't
  /// accidentally start spraying request bodies into their telemetry —
  /// opt in explicitly (typically guarded by `kDebugMode`).
  final bool enableHttpLog;

  /// Sink for SDK observability metrics. When wired, the HTTP layer,
  /// real-time transport and offline queue emit numeric counters
  /// (e.g. `http_request_duration_ms`, `http_error`, `ws_disconnect`,
  /// `offline_queue_depth`) that downstream telemetry can forward to
  /// Prometheus, Datadog, Firebase Performance, etc. Defaults to
  /// `null` (no metrics emitted).
  @experimental
  final MetricCallback? metricCallback;

  /// SHA-256 fingerprints (hex, colons optional, case-insensitive) of the
  /// leaf certificates intended for pinning.
  ///
  /// **Not enforced yet — experimental.** The
  /// `CertificatePinningInterceptor` attached when this list is non-empty is
  /// an `@experimental` skeleton: it normalises and records the pins and maps
  /// a Dio-surfaced handshake error to a typed `CertificatePinningException`,
  /// but it does **not** install the native `badCertificateCallback`/HTTP
  /// adapter that would actually compare the presented certificate against
  /// these pins. **Setting this list does NOT protect against MITM today.**
  /// A `warn` log is emitted at construction to make that explicit. The field
  /// exists so the public API stays stable while the platform plumbing
  /// matures; treat it as a no-op until a release note says otherwise.
  ///
  /// Default `null` → the platform's trust store is used directly. On web
  /// pinning will always be a no-op (the browser owns the TLS handshake);
  /// use HSTS + CT logs instead.
  final List<String>? certificatePins;

  String get effectiveSseUrl => sseUrl ?? realtimeUrl;

  /// Default logger that routes `(level, message)` calls to
  /// [developer.log] under the `'noma_chat'` source, mapping the level
  /// string to the numeric values used by Dart DevTools (`debug=500`,
  /// `info=800`, `warn=900`, `error=1000`, anything else `800`).
  ///
  /// Useful as a sensible default for apps that don't have their own
  /// telemetry pipeline yet:
  ///
  /// ```dart
  /// final chat = await NomaChat.create(
  ///   baseUrl: '...',
  ///   realtimeUrl: '...',
  ///   tokenProvider: () async => '...',
  ///   currentUser: ChatUser(id: '...', displayName: '...'),
  ///   logger: ChatConfig.developerLogger,
  /// );
  /// ```
  ///
  /// In release builds calls are still forwarded to [developer.log] but
  /// most release tooling silently discards them, so there's no
  /// performance penalty in production.
  @experimental
  static void developerLogger(String level, String message) {
    final levelValue = switch (level) {
      'debug' => 500,
      'info' => 800,
      'warn' => 900,
      'error' => 1000,
      _ => 800,
    };
    developer.log(message, name: 'noma_chat', level: levelValue);
  }

  /// Same as [developerLogger] but only forwards in debug builds (no-op
  /// in release). Use when you want zero overhead in production but a
  /// readable log stream during development.
  @experimental
  static void debugOnlyLogger(String level, String message) {
    if (!kDebugMode) return;
    developerLogger(level, message);
  }

  /// Private "kitchen sink" constructor that the three public ones
  /// delegate to. Centralises validation and avoids tripling the 17
  /// shared params in every constructor body.
  ChatConfig._({
    required this.baseUrl,
    required this.realtimeUrl,
    required this.authInterceptor,
    this.sseUrl,
    this.wsPath = '/ws',
    this.ssePath = '/eventsource',
    this.userId,
    this.onAuthFailure,
    this.actAsUserId,
    this.wsReconnectDelay = const Duration(seconds: 2),
    this.authTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.sseIdleTimeout = const Duration(seconds: 60),
    this.realtimeMode = RealtimeMode.auto,
    this.pollingConfig,
    this.retryConfig = const RetryConfig(),
    this.cacheConfig,
    this.localDatasource,
    this.maxReconnectAttempts,
    this.eventBufferSize = 20,
    this.enableReconnectCatchUp = false,
    this.logger,
    this.enableHttpLog = false,
    this.metricCallback,
    this.certificatePins,
  }) {
    _validate(baseUrl, realtimeUrl, sseUrl);
  }

  /// Creates a [ChatConfig] with bearer token authentication.
  ///
  /// This is the standard constructor for most production apps. It wires a
  /// [BearerAuthInterceptor] that calls [tokenProvider] on every request that
  /// needs a fresh JWT.
  ///
  /// **Required parameters:**
  ///
  /// [baseUrl] — full REST base URL including the API version prefix, e.g.
  /// `https://chat.myapp.com/v1`. Must not end with `/`. Must use `https://`
  /// in release builds.
  ///
  /// [realtimeUrl] — HTTP base used to derive the WebSocket URL
  /// (`wss://host/ws`) and the SSE URL (`https://host/events`). The SDK
  /// converts the scheme automatically. Must not end with `/`.
  ///
  /// [tokenProvider] — async function that returns a valid bearer token. Called
  /// before each request and on 401 responses to refresh the token. Must not
  /// throw; return an empty string to signal an unauthenticated state.
  ///
  /// **Optional connection parameters:**
  ///
  /// [onAuthFailure] — called when [tokenProvider] returns an empty / invalid
  /// token or the server returns 401 after a refresh attempt. Use to trigger
  /// a logout flow in the host app.
  ///
  /// [sseUrl] — override the base URL used for the SSE endpoint. Defaults to
  /// [realtimeUrl].
  ///
  /// [realtimeMode] — transport strategy. Defaults to [RealtimeMode.auto]
  /// (WebSocket primary, SSE fallback). Use [RealtimeMode.polling] for
  /// environments where WebSockets are blocked.
  ///
  /// [requestTimeout] — maximum duration for a single HTTP request before a
  /// [ChatNetworkException] is raised. Defaults to 30 seconds.
  ///
  /// [retryConfig] — controls automatic retry behaviour (attempts, back-off).
  /// Defaults to [RetryConfig] defaults.
  ///
  /// [maxReconnectAttempts] — maximum number of automatic WebSocket / SSE
  /// reconnect attempts before giving up. `null` means unlimited.
  ///
  /// **Cache parameters:**
  ///
  /// [cacheConfig] — enables the in-memory TTL cache and offline queue. When
  /// `null` every call goes directly to the network. When provided, pair it
  /// with a non-null [localDatasource] for persistence across app restarts.
  ///
  /// [localDatasource] — pluggable persistent store. Use [HiveChatDatasource]
  /// (the bundled default) or supply your own implementation.
  ///
  /// **Observability parameters:**
  ///
  /// [logger] — `(level, message)` sink for SDK log output. Levels are
  /// `'debug'`, `'info'`, `'warn'`, `'error'`. Use [ChatConfig.developerLogger]
  /// or [ChatConfig.debugOnlyLogger] for zero-configuration logging. When
  /// `null` (default) no logs are emitted.
  ///
  /// [enableHttpLog] — when `true` AND [logger] is non-null, attaches a Dio
  /// interceptor that logs each HTTP request and response (bodies truncated to
  /// 512 chars). Defaults to `false`. Opt in explicitly; typically guarded by
  /// `kDebugMode`.
  ///
  /// [metricCallback] — sink for numeric SDK counters (request durations,
  /// error counts, queue depth, etc.). Forward to Prometheus, Datadog,
  /// Firebase Performance, or any other telemetry backend. `null` by default.
  ///
  /// [certificatePins] — SHA-256 fingerprints of leaf certificates for
  /// pinning. **Experimental and not enforced yet** — see the field doc on
  /// [ChatConfig.certificatePins]. Setting it records the pins and emits a
  /// `warn` log but does not currently validate certificates or protect
  /// against MITM. `null` (default) uses the platform trust store.
  ///
  /// **Other parameters:**
  ///
  /// [userId] — the ID of the current user. When set, the SDK uses it for
  /// presence, typing indicators, and to populate `from` on optimistic messages.
  ///
  /// [enableReconnectCatchUp] — when `true`, the SDK fetches unread rooms
  /// immediately after every reconnect to surface messages received while
  /// offline. Defaults to `false`.
  ///
  /// [eventBufferSize] — capacity of the in-memory broadcast stream buffer.
  /// `0` (default) means no buffering (standard Dart broadcast stream).
  ///
  /// Throws [ArgumentError] if any URL is malformed, ends with `/`, uses
  /// `ws://`/`wss://` scheme, or uses `http://` in a release build.
  ///
  /// Example:
  /// ```dart
  /// final config = ChatConfig(
  ///   baseUrl: 'https://chat.myapp.com/v1',
  ///   realtimeUrl: 'https://chat.myapp.com',
  ///   tokenProvider: () => authService.getBearerToken(),
  ///   userId: currentUserId,
  ///   cacheConfig: CacheConfig(maxMessagesPerRoom: 500),
  ///   localDatasource: myHiveDatasource,
  ///   logger: ChatConfig.debugOnlyLogger,
  /// );
  /// ```
  factory ChatConfig({
    required String baseUrl,
    required String realtimeUrl,
    required Future<String> Function() tokenProvider,
    void Function()? onAuthFailure,
    String? sseUrl,
    String wsPath = '/ws',
    String ssePath = '/eventsource',
    String? userId,
    String? actAsUserId,
    Duration wsReconnectDelay = const Duration(seconds: 2),
    Duration authTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration? sseIdleTimeout = const Duration(seconds: 60),
    RealtimeMode realtimeMode = RealtimeMode.auto,
    PollingConfig? pollingConfig,
    RetryConfig retryConfig = const RetryConfig(),
    CacheConfig? cacheConfig,
    ChatLocalDatasource? localDatasource,
    int? maxReconnectAttempts,
    int eventBufferSize = 20,
    bool enableReconnectCatchUp = false,
    void Function(String level, String message)? logger,
    bool enableHttpLog = false,
    MetricCallback? metricCallback,
    List<String>? certificatePins,
  }) {
    return ChatConfig._(
      baseUrl: baseUrl,
      realtimeUrl: realtimeUrl,
      authInterceptor: BearerAuthInterceptor(
        tokenProvider: tokenProvider,
        onAuthFailure: onAuthFailure,
        logger: logger,
      ),
      sseUrl: sseUrl,
      wsPath: wsPath,
      ssePath: ssePath,
      userId: userId,
      onAuthFailure: onAuthFailure,
      actAsUserId: actAsUserId,
      wsReconnectDelay: wsReconnectDelay,
      authTimeout: authTimeout,
      requestTimeout: requestTimeout,
      sseIdleTimeout: sseIdleTimeout,
      realtimeMode: realtimeMode,
      pollingConfig: pollingConfig,
      retryConfig: retryConfig,
      cacheConfig: cacheConfig,
      localDatasource: localDatasource,
      maxReconnectAttempts: maxReconnectAttempts,
      eventBufferSize: eventBufferSize,
      enableReconnectCatchUp: enableReconnectCatchUp,
      logger: logger,
      enableHttpLog: enableHttpLog,
      metricCallback: metricCallback,
      certificatePins: certificatePins,
    );
  }

  /// Creates a config with a custom [AuthInterceptor] for full control over authentication.
  factory ChatConfig.withAuthInterceptor({
    required String baseUrl,
    required String realtimeUrl,
    required AuthInterceptor authInterceptor,
    String? sseUrl,
    String wsPath = '/ws',
    String ssePath = '/eventsource',
    String? userId,
    void Function()? onAuthFailure,
    String? actAsUserId,
    Duration wsReconnectDelay = const Duration(seconds: 2),
    Duration authTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration? sseIdleTimeout = const Duration(seconds: 60),
    RealtimeMode realtimeMode = RealtimeMode.auto,
    PollingConfig? pollingConfig,
    RetryConfig retryConfig = const RetryConfig(),
    CacheConfig? cacheConfig,
    ChatLocalDatasource? localDatasource,
    int? maxReconnectAttempts,
    int eventBufferSize = 20,
    bool enableReconnectCatchUp = false,
    void Function(String level, String message)? logger,
    bool enableHttpLog = false,
    MetricCallback? metricCallback,
    List<String>? certificatePins,
  }) {
    return ChatConfig._(
      baseUrl: baseUrl,
      realtimeUrl: realtimeUrl,
      authInterceptor: authInterceptor,
      sseUrl: sseUrl,
      wsPath: wsPath,
      ssePath: ssePath,
      userId: userId,
      onAuthFailure: onAuthFailure,
      actAsUserId: actAsUserId,
      wsReconnectDelay: wsReconnectDelay,
      authTimeout: authTimeout,
      requestTimeout: requestTimeout,
      sseIdleTimeout: sseIdleTimeout,
      realtimeMode: realtimeMode,
      pollingConfig: pollingConfig,
      retryConfig: retryConfig,
      cacheConfig: cacheConfig,
      localDatasource: localDatasource,
      maxReconnectAttempts: maxReconnectAttempts,
      eventBufferSize: eventBufferSize,
      enableReconnectCatchUp: enableReconnectCatchUp,
      logger: logger,
      enableHttpLog: enableHttpLog,
      metricCallback: metricCallback,
      certificatePins: certificatePins,
    );
  }

  /// Creates a config with HTTP Basic authentication.
  factory ChatConfig.withBasicAuth({
    required String baseUrl,
    required String realtimeUrl,
    required String username,
    required String password,
    String? sseUrl,
    String wsPath = '/ws',
    String ssePath = '/eventsource',
    String? userId,
    void Function()? onAuthFailure,
    String? actAsUserId,
    Duration wsReconnectDelay = const Duration(seconds: 2),
    Duration authTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration? sseIdleTimeout = const Duration(seconds: 60),
    RealtimeMode realtimeMode = RealtimeMode.auto,
    PollingConfig? pollingConfig,
    RetryConfig retryConfig = const RetryConfig(),
    CacheConfig? cacheConfig,
    ChatLocalDatasource? localDatasource,
    int? maxReconnectAttempts,
    int eventBufferSize = 20,
    bool enableReconnectCatchUp = false,
    void Function(String level, String message)? logger,
    bool enableHttpLog = false,
    MetricCallback? metricCallback,
    List<String>? certificatePins,
  }) {
    return ChatConfig._(
      baseUrl: baseUrl,
      realtimeUrl: realtimeUrl,
      authInterceptor: BasicAuthInterceptor(
        username: username,
        password: password,
      ),
      sseUrl: sseUrl,
      wsPath: wsPath,
      ssePath: ssePath,
      userId: userId,
      onAuthFailure: onAuthFailure,
      actAsUserId: actAsUserId,
      wsReconnectDelay: wsReconnectDelay,
      authTimeout: authTimeout,
      requestTimeout: requestTimeout,
      sseIdleTimeout: sseIdleTimeout,
      realtimeMode: realtimeMode,
      pollingConfig: pollingConfig,
      retryConfig: retryConfig,
      cacheConfig: cacheConfig,
      localDatasource: localDatasource,
      maxReconnectAttempts: maxReconnectAttempts,
      eventBufferSize: eventBufferSize,
      enableReconnectCatchUp: enableReconnectCatchUp,
      logger: logger,
      enableHttpLog: enableHttpLog,
      metricCallback: metricCallback,
      certificatePins: certificatePins,
    );
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
