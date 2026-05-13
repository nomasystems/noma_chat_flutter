import 'circuit_breaker.dart';

class CircuitBreakerRegistry {
  final int failureThreshold;
  final Duration openTimeout;
  final Map<String, CircuitBreaker> _breakers = {};

  CircuitBreakerRegistry({
    this.failureThreshold = 5,
    this.openTimeout = const Duration(seconds: 30),
  });

  CircuitBreaker forPath(String path) {
    final group = _extractGroup(path);
    return _breakers.putIfAbsent(
      group,
      () => CircuitBreaker(
        failureThreshold: failureThreshold,
        openTimeout: openTimeout,
      ),
    );
  }

  String _extractGroup(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    for (final segment in segments) {
      if (segment != 'v1' && segment != 'internal') return segment;
    }
    return '_default';
  }

  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
    _breakers.clear();
  }
}
