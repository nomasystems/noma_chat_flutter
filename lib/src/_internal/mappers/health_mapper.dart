import '../../models/health_status.dart';
import '../util/json_safe.dart';

class HealthMapper {
  static HealthStatus fromJson(Map<String, dynamic> json) => HealthStatus(
    status: json['status'] == 'ok' ? ServiceStatus.ok : ServiceStatus.degraded,
    checks:
        jsonMapOrNull(json['checks'])?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
  );
}
