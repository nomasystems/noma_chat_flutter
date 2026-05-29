import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

import '../../config/chat_config.dart';
import '../cache/cache_manager.dart' show MetricCallback;
import 'bearer_auth_interceptor.dart';
import 'cert_pinning_interceptor.dart';
import 'chat_exception.dart';
import 'circuit_breaker_registry.dart';
import 'retry_interceptor.dart';

/// SDK semantic version surfaced via the `X-Noma-Chat-Version` header
/// and the `User-Agent` string. Kept in sync with `pubspec.yaml`
/// manually for now (a future build_runner-generated constant can drop
/// in here without changing the call sites).
const String nomaChatSdkVersion = '0.6.0';

const String _requestIdExtraKey = 'requestId';
const Uuid _uuid = Uuid();

class RestClient {
  final Dio _dio;
  final String? _userId;
  final void Function(String level, String message)? _logger;
  final MetricCallback? _metricCallback;
  final Set<CancelToken> _pendingTokens = <CancelToken>{};

  RestClient({required ChatConfig config, Dio? dio})
    : _dio = dio ?? Dio(),
      _userId = config.userId,
      _logger = config.logger,
      _metricCallback = config.metricCallback {
    _dio.options.baseUrl = config.baseUrl;
    _dio.options.connectTimeout = config.requestTimeout;
    _dio.options.receiveTimeout = config.requestTimeout;
    _dio.options.sendTimeout = config.requestTimeout;
    final pins = config.certificatePins;
    if (pins != null && pins.isNotEmpty) {
      final pinning = CertificatePinningInterceptor(pins)..attach(_dio);
      _dio.interceptors.add(pinning);
    }
    final authInterceptor = config.authInterceptor;
    _dio.interceptors.add(authInterceptor);
    if (authInterceptor is BearerAuthInterceptor) {
      authInterceptor.bindDio(_dio);
    }
    if (config.retryConfig.enabled) {
      _dio.interceptors.add(
        RetryInterceptor(
          config: config.retryConfig,
          dio: _dio,
          registry: CircuitBreakerRegistry(),
        ),
      );
    }
    _dio.interceptors.add(
      _ObservabilityInterceptor(
        metricCallback: _metricCallback,
        logger: _logger,
      ),
    );
    // The HTTP debug interceptor is opt-in: even when a logger is
    // wired, the consumer has to flip `enableHttpLog: true`
    // explicitly. Avoids spraying request bodies into telemetry when
    // apps wire a generic logger for adapter warnings.
    if (_logger != null && config.enableHttpLog) {
      _dio.interceptors.add(HttpDebugLogger(_logger));
    }
  }

  String? get userId => _userId;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      'GET',
      path,
      queryParams: queryParams,
      headers: headers,
    );
    return _asMap(response);
  }

  Future<(Map<String, dynamic>, int?)> getWithTotalCount(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      'GET',
      path,
      queryParams: queryParams,
      headers: headers,
    );
    final totalCount = int.tryParse(
      response.headers.value('x-total-count') ?? '',
    );
    return (_asMap(response), totalCount);
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      'GET',
      path,
      queryParams: queryParams,
      headers: headers,
    );
    if (response.data is List) return response.data as List<dynamic>;
    throw ChatApiException(
      statusCode: 0,
      body: response.data,
      message: 'Expected List but got ${response.data.runtimeType}',
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      'POST',
      path,
      data: data,
      queryParams: queryParams,
      headers: headers,
    );
    if (response.data == null || response.data == '') {
      return const {};
    }
    return response.data as Map<String, dynamic>;
  }

  Future<void> postVoid(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    await _request(
      'POST',
      path,
      data: data,
      queryParams: queryParams,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    final response = await _request('PUT', path, data: data, headers: headers);
    if (response.data == null || response.data == '') {
      return const {};
    }
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    return const {};
  }

  Future<void> putVoid(
    String path, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    await _request('PUT', path, data: data, headers: headers);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      'PATCH',
      path,
      data: data,
      headers: headers,
    );
    if (response.data == null || response.data == '') {
      return const {};
    }
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    return const {};
  }

  Future<void> delete(String path, {Map<String, String>? headers}) async {
    await _request('DELETE', path, headers: headers);
  }

  Future<Map<String, dynamic>> uploadBinary(
    String path,
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final response = await _request(
      'POST',
      path,
      data: Stream.fromIterable([data]),
      headers: {'content-type': mimeType},
      options: Options(
        contentType: mimeType,
        headers: {'content-length': data.length},
      ),
      onSendProgress: onProgress,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Uint8List> downloadBinary(
    String path, {
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _request(
      'GET',
      path,
      headers: headers,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );
    return Uint8List.fromList(response.data as List<int>);
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    Options? options,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final opts = options ?? Options();
    opts.method = method;
    final mergedHeaders = <String, String>{...?headers};
    if (mergedHeaders.isNotEmpty) {
      opts.headers = {...?opts.headers, ...mergedHeaders};
    }
    final autoHeaders = _autoHeaders(opts.headers);
    opts.headers = {...?opts.headers, ...autoHeaders};

    final requestId = _uuid.v4();
    opts.extra = {...?opts.extra, _requestIdExtraKey: requestId};

    final cancelToken = CancelToken();
    _pendingTokens.add(cancelToken);
    try {
      return await _dio.request(
        path,
        data: data,
        queryParameters: queryParams,
        options: opts,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    } finally {
      _pendingTokens.remove(cancelToken);
    }
  }

  /// Computes the headers automatically injected on every request:
  /// `X-Noma-Chat-Version` and `User-Agent`. Consumer-supplied values
  /// for either header (case-insensitive) win, so apps with their own
  /// `User-Agent` policy aren't overridden.
  Map<String, String> _autoHeaders(Map<String, dynamic>? existing) {
    final lower = <String>{
      for (final k in (existing ?? const <String, dynamic>{}).keys)
        k.toLowerCase(),
    };
    final out = <String, String>{};
    if (!lower.contains('x-noma-chat-version')) {
      out['X-Noma-Chat-Version'] = nomaChatSdkVersion;
    }
    if (!lower.contains('user-agent')) {
      out['User-Agent'] = 'noma_chat/$nomaChatSdkVersion (${_platformLabel()})';
    }
    return out;
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Cancels every in-flight HTTP request.
  ///
  /// Use on logout/dispose so pending REST calls do not race against
  /// a tokenProvider that has been invalidated. The cancelled futures
  /// complete with a `DioException` of type `cancel`, which downstream
  /// interceptors (auth, retry) must treat as a terminal failure
  /// rather than a retry trigger.
  void cancelPending([String reason = 'cancelled']) {
    final snapshot = List<CancelToken>.from(_pendingTokens);
    _pendingTokens.clear();
    for (final token in snapshot) {
      if (!token.isCancelled) {
        token.cancel(reason);
      }
    }
  }

  ChatException _mapDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final body = e.response?.data;

    if (statusCode == 400) {
      final detail = _extractMessage(body) ?? 'Bad request';
      if (detail.toLowerCase().contains('content filter')) {
        return ChatContentFilterException(detail);
      }
      return ChatValidationException(
        message: detail,
        errors: body is Map<String, dynamic> ? body : null,
      );
    }
    if (statusCode == 401) return const ChatAuthException();
    if (statusCode == 403) {
      // Account-level deactivation manifests as 403 with detail
      // `user_deactivated` (server-side: `is_active(UserId) == false`).
      // Surface as an auth exception so the consumer's `onAuthFailure`
      // hook fires and the SDK can drive the example/host app back to
      // the login flow. Other 403s (room ban, missing membership) stay
      // as `ChatForbiddenException` so callers can keep handling them
      // contextually (snackbar etc.).
      final detail = _extractMessage(body)?.toLowerCase() ?? '';
      if (detail.contains('user_deactivated') ||
          detail.contains('account_deactivated') ||
          detail.contains('account_banned')) {
        return const ChatAuthException('Account deactivated');
      }
      return ChatForbiddenException(
        body: body,
        message: e.message ?? 'Forbidden',
      );
    }
    if (statusCode == 404) return const ChatNotFoundException();
    if (statusCode == 409) {
      return ChatConflictException(_extractMessage(body) ?? 'Conflict');
    }
    if (statusCode == 429) {
      final retryAfterHeader = e.response?.headers.value('retry-after');
      Duration? retryAfter;
      if (retryAfterHeader != null) {
        final seconds = int.tryParse(retryAfterHeader);
        if (seconds != null) retryAfter = Duration(seconds: seconds);
      }
      return ChatRateLimitException(retryAfter: retryAfter);
    }
    if (e.error is CertificatePinningException) {
      return e.error as CertificatePinningException;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const ChatTimeoutException();
    }
    if (e.type == DioExceptionType.connectionError) {
      return const ChatNetworkException();
    }
    return ChatApiException(
      statusCode: statusCode ?? 0,
      body: body,
      message: e.message ?? 'Unknown error',
    );
  }

  Map<String, dynamic> _asMap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data == null || data == '') return const {};
    throw ChatApiException(
      statusCode: response.statusCode ?? 0,
      body: data,
      message: 'Expected Map but got ${data.runtimeType}',
    );
  }

  String? _extractMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      return body['detail'] as String? ?? body['message'] as String?;
    }
    return null;
  }
}

/// Sanitizes the rendered URI in a log line by replacing any UUID
/// path segment with its first five characters and an ellipsis. UUIDs
/// can leak room/user/message ids into shared log aggregators; this
/// keeps enough prefix for correlation while shrinking the cardinality
/// of personally-identifiable values.
String sanitizeUuidsInLogLine(String input) {
  return input.replaceAllMapped(_uuidPattern, (m) {
    final raw = m.group(0)!;
    final prefix = raw.length >= 5 ? raw.substring(0, 5) : raw;
    return '<UUID:$prefix...>';
  });
}

final RegExp _uuidPattern = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);

/// Wires `MetricCallback` emission into the Dio request lifecycle:
///
/// - `http_request_duration_ms` on every response (success or error
///   with a status code), tagged with `{path, method, status,
///   requestId}`.
/// - `http_error` on every error path, tagged with the same context
///   plus a `type` string derived from `DioExceptionType`.
class _ObservabilityInterceptor extends Interceptor {
  _ObservabilityInterceptor({
    required this.metricCallback,
    required this.logger,
  });

  final MetricCallback? metricCallback;
  final void Function(String level, String message)? logger;

  static const String _startedAtExtraKey = '_noma_started_at_ms';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtExtraKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _emitDuration(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _emitDuration(err.requestOptions, err.response?.statusCode);
    metricCallback?.call('http_error', {
      'path': err.requestOptions.path,
      'method': err.requestOptions.method,
      'status': err.response?.statusCode ?? 0,
      'type': err.type.name,
      if (err.requestOptions.extra[_requestIdExtraKey] != null)
        'requestId': err.requestOptions.extra[_requestIdExtraKey] as String,
    });
    handler.next(err);
  }

  void _emitDuration(RequestOptions options, int? status) {
    final startedAt = options.extra[_startedAtExtraKey];
    if (startedAt is! int) return;
    final duration = DateTime.now().millisecondsSinceEpoch - startedAt;
    metricCallback?.call('http_request_duration_ms', {
      'path': options.path,
      'method': options.method,
      'status': status ?? 0,
      'duration_ms': duration,
      if (options.extra[_requestIdExtraKey] != null)
        'requestId': options.extra[_requestIdExtraKey] as String,
    });
  }
}

/// Lightweight HTTP request/response logger attached only when the consumer
/// provides a `ChatConfig.logger`. Emits one `debug` line per request with
/// method, path and a truncated body, and one `debug` line per response
/// with status code; failures land at `warn` with the error body.
///
/// Sensitive values (passwords, tokens, auth headers) are redacted before
/// the body is rendered, both inside JSON maps and inside form-encoded or
/// query-style strings. Binary bodies (`FormData`, byte lists, streams)
/// are summarized as `<binary N bytes>` instead of being dumped verbatim.
///
/// Truncation keeps log volume bounded for large payloads — at most 512
/// chars of the rendered body are emitted.
class HttpDebugLogger extends Interceptor {
  HttpDebugLogger(this._logger);

  final void Function(String level, String message) _logger;

  static const int _maxBodyChars = 512;
  static const String _redacted = '<redacted>';

  static const Set<String> _sensitiveKeys = {
    'password',
    'passwd',
    'secret',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'api_key',
    'apikey',
    'authorization',
    'auth',
    'credential',
    'credentials',
    'pin',
    'otp',
  };

  static const Set<String> _sensitiveHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  };

  static final RegExp _formEncodedRegex = RegExp(
    // Value terminates only at `&` or end-of-string. Stopping at \s would
    // leak the part of the value after the first whitespace
    // (e.g. `authorization=Bearer real-token` would expose `real-token`).
    r'(password|passwd|secret|token|access_token|refresh_token|id_token|api_key|apikey|authorization|auth|credential|credentials|pin|otp)=([^&]+)',
    caseSensitive: false,
  );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestId = options.extra[_requestIdExtraKey];
    final reqTag = requestId is String ? _shortReqId(requestId) : null;
    final uri = sanitizeUuidsInLogLine(options.uri.toString());
    final prefix = reqTag != null ? 'req[$reqTag] ' : '';
    _logger(
      'debug',
      '$prefix'
          'http.req ${options.method} $uri body=${_renderBody(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final requestId = response.requestOptions.extra[_requestIdExtraKey];
    final reqTag = requestId is String ? _shortReqId(requestId) : null;
    final uri = sanitizeUuidsInLogLine(response.requestOptions.uri.toString());
    final prefix = reqTag != null ? 'req[$reqTag] ' : '';
    _logger(
      'debug',
      '$prefix'
          'http.res ${response.requestOptions.method} $uri status=${response.statusCode}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestId = err.requestOptions.extra[_requestIdExtraKey];
    final reqTag = requestId is String ? _shortReqId(requestId) : null;
    final uri = sanitizeUuidsInLogLine(err.requestOptions.uri.toString());
    final prefix = reqTag != null ? 'req[$reqTag] ' : '';
    _logger(
      'warn',
      '$prefix'
          'http.err ${err.requestOptions.method} $uri '
          'status=${err.response?.statusCode} body=${_renderBody(err.response?.data)}',
    );
    handler.next(err);
  }

  String renderBody(dynamic body) => _renderBody(body);

  String _renderBody(dynamic body) {
    if (body == null) return '∅';
    final summary = _summarizeBinary(body);
    if (summary != null) return summary;

    final redacted = _redact(body);
    final rendered = redacted is String ? redacted : redacted.toString();
    if (rendered.length <= _maxBodyChars) return rendered;
    return '${rendered.substring(0, _maxBodyChars)}…[+${rendered.length - _maxBodyChars}c]';
  }

  String? _summarizeBinary(dynamic body) {
    if (body is FormData) {
      var bytes = 0;
      for (final file in body.files) {
        bytes += file.value.length;
      }
      return '<binary $bytes bytes>';
    }
    if (body is Uint8List) return '<binary ${body.length} bytes>';
    if (body is List<int>) return '<binary ${body.length} bytes>';
    if (body is Stream) return '<binary stream>';
    return null;
  }

  dynamic _redact(dynamic body) {
    if (body is Map) {
      return _redactMap(body);
    }
    if (body is List) {
      return body.map(_redact).toList();
    }
    if (body is String) {
      return _redactString(body);
    }
    return body;
  }

  Map<String, dynamic> _redactMap(Map<dynamic, dynamic> source) {
    final out = <String, dynamic>{};
    source.forEach((key, value) {
      final k = key.toString();
      if (_isSensitiveKey(k)) {
        out[k] = _redacted;
      } else {
        out[k] = _redact(value);
      }
    });
    return out;
  }

  String _redactString(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final parsed = jsonDecode(body);
        final redacted = _redact(parsed);
        return jsonEncode(redacted);
      } catch (_) {
        // fall through to form-encoded handling
      }
    }
    return body.replaceAllMapped(
      _formEncodedRegex,
      (m) => '${m.group(1)}=$_redacted',
    );
  }

  bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    if (_sensitiveKeys.contains(lower)) return true;
    // Strip non-letter chars so `PASS_WORD`, `current.password` and similar
    // separator-broken variants collapse to an exact match in _sensitiveKeys
    // (e.g. `PASS_WORD` → `password`). Substring matching is intentionally
    // applied only to the original lowercase key so that composites like
    // `mypass-word` (normalises to `mypassword`, which contains `password`)
    // do not trigger a false positive.
    final normalised = lower.replaceAll(RegExp('[^a-z]'), '');
    if (_sensitiveKeys.contains(normalised)) return true;
    for (final needle in _sensitiveKeys) {
      if (lower.contains(needle)) return true;
    }
    return false;
  }

  static String _shortReqId(String requestId) {
    if (requestId.length <= 6) return requestId;
    return requestId.substring(0, 6);
  }

  static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    final out = <String, dynamic>{};
    headers.forEach((key, value) {
      if (_sensitiveHeaders.contains(key.toLowerCase())) {
        out[key] = _redacted;
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}
