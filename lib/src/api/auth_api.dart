import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/health_mapper.dart';
import '../core/result.dart';
import '../models/health_status.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatAuthApi] backed by the SDK's HTTP client.
class AuthApi implements ChatAuthApi {
  final RestClient _rest;

  AuthApi({required RestClient rest}) : _rest = rest;

  @override
  Future<Result<HealthStatus>> healthCheck() =>
      safeApiCall(() async {
        final json = await _rest.get('/health');
        return HealthMapper.fromJson(json);
      });
}
