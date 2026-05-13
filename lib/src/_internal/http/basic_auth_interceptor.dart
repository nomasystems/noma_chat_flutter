import 'dart:convert';

import 'auth_interceptor.dart';

/// HTTP Basic authentication using a fixed username and password.
class BasicAuthInterceptor extends AuthInterceptor {
  final String username;
  final String password;

  BasicAuthInterceptor({required this.username, required this.password});

  @override
  Future<String> getAuthHeader() async {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }
}
