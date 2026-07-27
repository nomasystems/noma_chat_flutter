import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/in_flight_registry.dart';

void main() {
  group('InFlightRegistry', () {
    test(
      'a second run() with the same key while the first is pending '
      'shares the first Future instead of invoking the operation again',
      () async {
        var invocationCount = 0;
        final completer = Completer<String>();
        final registry = InFlightRegistry();

        final first = registry.run('key-1', () {
          invocationCount++;
          return completer.future;
        });
        final second = registry.run('key-1', () {
          invocationCount++;
          return completer.future;
        });

        completer.complete('done');
        final results = await Future.wait([first, second]);

        expect(invocationCount, 1);
        expect(results, ['done', 'done']);
      },
    );

    test('a different key runs independently and concurrently', () async {
      var invocationCount = 0;
      final registry = InFlightRegistry();

      final first = registry.run('key-a', () async {
        invocationCount++;
        return 'a';
      });
      final second = registry.run('key-b', () async {
        invocationCount++;
        return 'b';
      });

      final results = await Future.wait([first, second]);

      expect(invocationCount, 2);
      expect(results, ['a', 'b']);
    });

    test('the key is evicted once the in-flight future settles, so a genuine '
        'follow-up call runs again', () async {
      var invocationCount = 0;
      final registry = InFlightRegistry();

      await registry.run('key-1', () async {
        invocationCount++;
        return 'first';
      });
      expect(registry.length, 0);

      await registry.run('key-1', () async {
        invocationCount++;
        return 'second';
      });

      expect(invocationCount, 2);
    });

    test('the key is evicted even when the operation fails', () async {
      final registry = InFlightRegistry();

      await expectLater(
        registry.run('key-1', () async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );

      expect(registry.length, 0);
    });
  });

  group('canonicalRequestKey', () {
    test('is identical regardless of map key insertion order', () {
      final a = canonicalRequestKey('POST', '/rooms', {
        'name': 'Room A',
        'audience': 'contacts',
      });
      final b = canonicalRequestKey('POST', '/rooms', {
        'audience': 'contacts',
        'name': 'Room A',
      });

      expect(a, b);
    });

    test('differs when method, path or body differ', () {
      final base = canonicalRequestKey('POST', '/rooms', {'name': 'A'});
      expect(base, isNot(canonicalRequestKey('PUT', '/rooms', {'name': 'A'})));
      expect(
        base,
        isNot(canonicalRequestKey('POST', '/rooms/x', {'name': 'A'})),
      );
      expect(base, isNot(canonicalRequestKey('POST', '/rooms', {'name': 'B'})));
    });

    test('supports a null body for bodyless requests (e.g. DELETE)', () {
      final a = canonicalRequestKey('DELETE', '/rooms/r1/users/u1');
      final b = canonicalRequestKey('DELETE', '/rooms/r1/users/u1');
      expect(a, b);
    });
  });

  group('deriveIdempotencyKey', () {
    test('is deterministic for the same canonical key', () {
      final canonical = canonicalRequestKey('POST', '/rooms', {'name': 'A'});
      expect(deriveIdempotencyKey(canonical), deriveIdempotencyKey(canonical));
    });

    test('differs for a different canonical key', () {
      final keyA = canonicalRequestKey('POST', '/rooms', {'name': 'A'});
      final keyB = canonicalRequestKey('POST', '/rooms', {'name': 'B'});
      expect(deriveIdempotencyKey(keyA), isNot(deriveIdempotencyKey(keyB)));
    });
  });
}
