import '../../models/health_status.dart';

class HealthMapper {
  static HealthStatus fromJson(Map<String, dynamic> json) => HealthStatus(
        status: json['status'] == 'ok' ? ServiceStatus.ok : ServiceStatus.degraded,
        checks: (json['checks'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            {},
      );
}
