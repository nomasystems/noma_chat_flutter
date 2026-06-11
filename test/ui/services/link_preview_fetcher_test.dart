import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/services/link_preview_fetcher.dart';

void main() {
  group('LinkPreviewCacheStats.hitRate', () {
    test('is 0.0 before any fetch has happened', () {
      const stats = LinkPreviewCacheStats(
        entries: 0,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 0,
        misses: 0,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 0.0);
    });

    test('rounds hits / (hits + misses) to two decimals', () {
      const stats = LinkPreviewCacheStats(
        entries: 2,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 1,
        misses: 2,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 0.33);
    });

    test('is 1.0 when every lookup was a hit', () {
      const stats = LinkPreviewCacheStats(
        entries: 3,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 4,
        misses: 0,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 1.0);
    });
  });

  group('LinkPreviewCacheStats.toString', () {
    test('renders every counter and the derived hit rate', () {
      const stats = LinkPreviewCacheStats(
        entries: 5,
        capacity: 64,
        failures: 2,
        inFlight: 1,
        hits: 3,
        misses: 1,
        failureRetries: 1,
        evictions: 4,
      );

      final text = stats.toString();
      expect(text, contains('entries: 5/64'));
      expect(text, contains('failures: 2'));
      expect(text, contains('inFlight: 1'));
      expect(text, contains('hits: 3'));
      expect(text, contains('misses: 1'));
      expect(text, contains('failureRetries: 1'));
      expect(text, contains('evictions: 4'));
      expect(text, contains('hitRate: 0.75'));
    });
  });
}
