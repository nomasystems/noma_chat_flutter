enum CircuitState { closed, open, halfOpen }

class CircuitBreaker {
  final int failureThreshold;
  final Duration openTimeout;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _openedAt;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.openTimeout = const Duration(seconds: 30),
  });

  CircuitState get state => _state;

  bool allowRequest() {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        if (_openedAt != null &&
            DateTime.now().difference(_openedAt!) >= openTimeout) {
          _state = CircuitState.halfOpen;
          return true;
        }
        return false;
      case CircuitState.halfOpen:
        return true;
    }
  }

  void recordSuccess() {
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void recordFailure() {
    _failureCount++;
    if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
      _openedAt = DateTime.now();
    }
  }

  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _openedAt = null;
  }
}
