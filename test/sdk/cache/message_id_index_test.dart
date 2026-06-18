import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/cache/_message_id_index.dart';

void main() {
  group('MessageIdIndex.normalizedIso', () {
    test('truncates to millisecond precision (fixed 3-digit fraction)', () {
      final micros = DateTime.utc(2026, 6, 15, 10, 0, 0, 0, 123);
      expect(MessageIdIndex.normalizedIso(micros), '2026-06-15T10:00:00.000Z');
    });

    test('keeps lexicographic order == chronological across precisions', () {
      // A backend millisecond timestamp and a local microsecond one in the
      // same millisecond: raw toIso8601String() would sort the ms one AFTER
      // the µs one ('Z' > '1'), inverting order. Normalized keys must not.
      final backendMs = DateTime.utc(2026, 6, 15, 10, 0, 0, 0);
      final localMicros = DateTime.utc(2026, 6, 15, 10, 0, 0, 0, 123);

      final kBackend = MessageIdIndex.keyFor(backendMs, 'a');
      final kLocal = MessageIdIndex.keyFor(localMicros, 'b');

      // Truncated to the same millisecond, so they tie on the timestamp
      // prefix and the id suffix breaks the tie deterministically — never
      // an inverted chronological order.
      expect(kBackend.compareTo(kLocal) < 0, isTrue);
    });

    test('later millisecond sorts after earlier one', () {
      final earlier = DateTime.utc(2026, 6, 15, 10, 0, 0, 5);
      final later = DateTime.utc(2026, 6, 15, 10, 0, 0, 6);
      final kEarlier = MessageIdIndex.keyFor(earlier, 'z');
      final kLater = MessageIdIndex.keyFor(later, 'a');
      expect(kEarlier.compareTo(kLater) < 0, isTrue);
    });

    test('normalizes to UTC', () {
      final local = DateTime(2026, 6, 15, 10).toLocal();
      expect(MessageIdIndex.normalizedIso(local).endsWith('Z'), isTrue);
    });
  });
}
