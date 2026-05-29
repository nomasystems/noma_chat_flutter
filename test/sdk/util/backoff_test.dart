import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/util/backoff.dart';

void main() {
  group('computeBackoffMs', () {
    test('attempt=0 with base=1000 yields [1000, 2000]', () {
      for (var seed = 0; seed < 20; seed++) {
        final ms = computeBackoffMs(
          attempt: 0,
          baseMs: 1000,
          random: Random(seed),
        );
        expect(ms, greaterThanOrEqualTo(1000));
        expect(ms, lessThanOrEqualTo(2000));
      }
    });

    test(
      'attempt=5 with base=1000, max=60000, jitter=1000 yields [32000, 33000]',
      () {
        for (var seed = 0; seed < 20; seed++) {
          final ms = computeBackoffMs(
            attempt: 5,
            baseMs: 1000,
            maxMs: 60000,
            jitterMs: 1000,
            random: Random(seed),
          );
          expect(ms, greaterThanOrEqualTo(32000));
          expect(ms, lessThanOrEqualTo(33000));
        }
      },
    );

    test('attempt=30 with base=1000, max=60000 is capped at 60000', () {
      for (var seed = 0; seed < 20; seed++) {
        final ms = computeBackoffMs(
          attempt: 30,
          baseMs: 1000,
          maxMs: 60000,
          random: Random(seed),
        );
        expect(ms, equals(60000));
      }
    });

    test('jitter never pushes result above maxMs (cap+jitter order)', () {
      for (var seed = 0; seed < 100; seed++) {
        final ms = computeBackoffMs(
          attempt: 6,
          baseMs: 1000,
          maxMs: 60000,
          jitterMs: 1000,
          random: Random(seed),
        );
        expect(ms, lessThanOrEqualTo(60000));
      }
    });

    test('seeded Random produces identical result across runs', () {
      final a = computeBackoffMs(attempt: 3, random: Random(42));
      final b = computeBackoffMs(attempt: 3, random: Random(42));
      expect(a, equals(b));
    });

    test('very large attempt does not overflow', () {
      final ms = computeBackoffMs(
        attempt: 1000,
        baseMs: 1000,
        maxMs: 60000,
        random: Random(0),
      );
      expect(ms, equals(60000));
    });

    test('jitterMs=0 disables jitter', () {
      final ms = computeBackoffMs(
        attempt: 2,
        baseMs: 1000,
        jitterMs: 0,
        random: Random(0),
      );
      expect(ms, equals(4000));
    });
  });
}
