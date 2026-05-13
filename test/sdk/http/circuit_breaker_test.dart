import 'package:noma_chat/src/_internal/http/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CircuitBreaker', () {
    test('starts closed', () {
      final cb = CircuitBreaker();
      expect(cb.state, CircuitState.closed);
      expect(cb.allowRequest(), isTrue);
    });

    test('opens after threshold failures', () {
      final cb = CircuitBreaker(failureThreshold: 3);
      cb.recordFailure();
      cb.recordFailure();
      expect(cb.state, CircuitState.closed);
      cb.recordFailure();
      expect(cb.state, CircuitState.open);
      expect(cb.allowRequest(), isFalse);
    });

    test('resets to closed on success', () {
      final cb = CircuitBreaker(failureThreshold: 2);
      cb.recordFailure();
      cb.recordFailure();
      expect(cb.state, CircuitState.open);
      cb.recordSuccess();
      expect(cb.state, CircuitState.closed);
    });

    test('transitions to half-open after timeout', () {
      final cb = CircuitBreaker(
        failureThreshold: 1,
        openTimeout: Duration.zero,
      );
      cb.recordFailure();
      expect(cb.state, CircuitState.open);
      expect(cb.allowRequest(), isTrue);
      expect(cb.state, CircuitState.halfOpen);
    });

    test('reset clears state', () {
      final cb = CircuitBreaker(failureThreshold: 1);
      cb.recordFailure();
      expect(cb.state, CircuitState.open);
      cb.reset();
      expect(cb.state, CircuitState.closed);
    });
  });
}
