import 'package:dio/dio.dart';

/// Base class for authentication interceptors that inject auth headers into HTTP requests.
abstract class AuthInterceptor extends Interceptor {
  Future<String> getAuthHeader();

  Future<String> getToken() async {
    final header = await getAuthHeader();
    if (header.startsWith('Bearer ')) return header.substring(7);
    if (header.startsWith('Basic ')) return header.substring(6);
    return header;
  }

  void invalidateCache() {}

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Authorization'] = await getAuthHeader();
    handler.next(options);
  }
}
