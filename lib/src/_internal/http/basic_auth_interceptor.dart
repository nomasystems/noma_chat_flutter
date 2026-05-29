import 'dart:convert';

import 'package:dio/dio.dart';

import 'auth_interceptor.dart';

/// HTTP Basic authentication using a fixed username and password.
class BasicAuthInterceptor extends AuthInterceptor {
  final String username;
  final String password;

  /// Optional callback fired when the server signals the account is no
  /// longer valid (HTTP 401, or 403 with `user_deactivated` /
  /// `account_deactivated` / `account_banned` in the body). Consumers
  /// typically wire this to a global "force logout" handler.
  ///
  /// Basic auth can't refresh anything, so retry doesn't make sense:
  /// the call fails, the consumer is signalled, and the host app is
  /// expected to drop the session and surface the login flow.
  final void Function()? onAuthFailure;

  BasicAuthInterceptor({
    required this.username,
    required this.password,
    this.onAuthFailure,
  });

  @override
  Future<String> getAuthHeader() async {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  /// Return the full `Basic <base64>` header instead of stripping the prefix.
  /// The realtime WS handshake sends `{type: auth, token: <getToken()>}`; the
  /// server-side handler (e.g. CHT `user_client_ws_handler:handle_auth/2`)
  /// inspects the token's prefix to choose the auth scheme. Without the
  /// `Basic ` prefix the token would be misclassified as a bearer JWT,
  /// fail JWT decoding, and the connection would close with `auth_error:
  /// invalid_token`.
  ///
  /// Bearer auth keeps the base behaviour (strip and ship the JWT bare) —
  /// see [AuthInterceptor.getToken] in `auth_interceptor.dart`.
  @override
  Future<String> getToken() async => getAuthHeader();

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    if (status == 401) {
      onAuthFailure?.call();
    } else if (status == 403) {
      final body = err.response?.data;
      // Match against the server-side reason strings rest_client also
      // recognises. Anything else (room ban, missing membership) stays
      // a regular 403 — we don't want to log the user out for those.
      final asString = body is String
          ? body.toLowerCase()
          : (body is Map<String, dynamic>
                ? (body['detail'] ?? body['error'] ?? '')
                      .toString()
                      .toLowerCase()
                : '');
      if (asString.contains('user_deactivated') ||
          asString.contains('account_deactivated') ||
          asString.contains('account_banned')) {
        onAuthFailure?.call();
      }
    }
    handler.next(err);
  }
}
