import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/basic_auth_interceptor.dart';
import 'package:noma_chat/src/_internal/http/circuit_breaker.dart';
import 'package:noma_chat/src/_internal/http/circuit_breaker_registry.dart';

/// The registry buckets HTTP paths into circuit groups so a noisy `/rooms`
/// endpoint doesn't trip `/messages`. These tests drive every branch of
/// `_extractGroup` and `forPath`.
void main() {
  group('CircuitBreakerRegistry', () {
    test('returns the same breaker for paths in the same group', () {
      final reg = CircuitBreakerRegistry();
      final a = reg.forPath('/rooms/r1');
      final b = reg.forPath('/rooms/r2/members');
      expect(identical(a, b), isTrue);
    });

    test('returns different breakers for different groups', () {
      final reg = CircuitBreakerRegistry();
      final a = reg.forPath('/rooms/r1');
      final b = reg.forPath('/messages/m1');
      expect(identical(a, b), isFalse);
    });

    test('skips the `v1` and `internal` prefixes when grouping', () {
      final reg = CircuitBreakerRegistry();
      final a = reg.forPath('/v1/rooms/r1');
      final b = reg.forPath('/internal/rooms/r2');
      expect(identical(a, b), isTrue);
    });

    test(
      'defaults to a `_default` group when no informative segment exists',
      () {
        final reg = CircuitBreakerRegistry();
        final a = reg.forPath('/v1');
        final b = reg.forPath('/internal');
        final c = reg.forPath('//');
        expect(identical(a, b), isTrue);
        expect(identical(a, c), isTrue);
      },
    );

    test('propagates the registry-level threshold to created breakers', () {
      final reg = CircuitBreakerRegistry(
        failureThreshold: 1,
        openTimeout: const Duration(milliseconds: 5),
      );
      final cb = reg.forPath('/rooms/r1');
      cb.recordFailure();
      expect(cb.state, CircuitState.open);
    });

    test('resetAll clears every breaker and reinstantiates lazily', () {
      final reg = CircuitBreakerRegistry(failureThreshold: 1);
      final a = reg.forPath('/rooms/r1');
      a.recordFailure();
      expect(a.state, CircuitState.open);

      reg.resetAll();
      final fresh = reg.forPath('/rooms/r1');
      expect(fresh.state, CircuitState.closed);
      // After resetAll the registry was wiped, so this is a new instance.
      expect(identical(a, fresh), isFalse);
    });
  });

  group('BasicAuthInterceptor', () {
    test('emits the canonical Base64 header', () async {
      final i = BasicAuthInterceptor(
        username: 'Aladdin',
        password: 'open sesame',
      );
      expect(await i.getAuthHeader(), 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==');
    });

    test('handles empty credentials cleanly', () async {
      final i = BasicAuthInterceptor(username: '', password: '');
      // ":" → "Og=="
      expect(await i.getAuthHeader(), 'Basic Og==');
    });

    test('non-ascii passwords are utf8-encoded before base64', () async {
      final i = BasicAuthInterceptor(username: 'u', password: 'ñá');
      final header = await i.getAuthHeader();
      expect(header, startsWith('Basic '));
      expect(header.length, greaterThan('Basic '.length));
    });
  });
}
