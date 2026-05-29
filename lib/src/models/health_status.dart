import 'package:freezed_annotation/freezed_annotation.dart';

part 'health_status.freezed.dart';

/// Server health status with individual service check results.
@freezed
abstract class HealthStatus with _$HealthStatus {
  const HealthStatus._();

  const factory HealthStatus({
    required ServiceStatus status,
    @Default(<String, String>{}) Map<String, String> checks,
  }) = _HealthStatus;

  bool get isHealthy => status == ServiceStatus.ok;
}

/// Outcome of a backend health check. `degraded` means the server responded
/// but some sub-systems are unhealthy.
enum ServiceStatus { ok, degraded }
