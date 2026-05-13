import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../config/chat_config.dart';
import 'bearer_auth_interceptor.dart';
import 'chat_exception.dart';
import 'circuit_breaker_registry.dart';
import 'retry_interceptor.dart';

class RestClient {
  final Dio _dio;
  final String? _userId;

  RestClient({required ChatConfig config, Dio? dio})
    : _dio = dio ?? Dio(),
      _userId = config.userId {
    _dio.options.baseUrl = config.baseUrl;
    _dio.options.connectTimeout = config.requestTimeout;
    _dio.options.receiveTimeout = config.requestTimeout;
    _dio.options.sendTimeout = config.requestTimeout;
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
    try {
      final opts = options ?? Options();
      opts.method = method;
      final mergedHeaders = <String, String>{...?headers};
      if (mergedHeaders.isNotEmpty) {
        opts.headers = {...?opts.headers, ...mergedHeaders};
      }

      return await _dio.request(
        path,
        data: data,
        queryParameters: queryParams,
        options: opts,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
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
