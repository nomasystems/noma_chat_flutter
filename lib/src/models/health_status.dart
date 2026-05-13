/// Server health status with individual service check results.
class HealthStatus {
  final ServiceStatus status;
  final Map<String, String> checks;

  const HealthStatus({required this.status, this.checks = const {}});

  bool get isHealthy => status == ServiceStatus.ok;
}

/// Outcome of a backend health check. `degraded` means the server responded
/// but some sub-systems are unhealthy.
enum ServiceStatus { ok, degraded }
