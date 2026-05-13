import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/date_formatter.dart';

void main() {
  final now = DateTime(2026, 3, 17, 14, 30);

  group('formatSeparator', () {
    test('returns Today for today', () {
      expect(DateFormatter.formatSeparator(now, now: now), 'Today');
    });

    test('returns Yesterday for yesterday', () {
      final yesterday = DateTime(2026, 3, 16, 10, 0);
      expect(DateFormatter.formatSeparator(yesterday, now: now), 'Yesterday');
    });

    test('returns dd/MM for same year', () {
      final date = DateTime(2026, 1, 5);
      expect(DateFormatter.formatSeparator(date, now: now), '05/01');
    });

    test('returns dd/MM/yyyy for different year', () {
      final date = DateTime(2025, 12, 25);
      expect(DateFormatter.formatSeparator(date, now: now), '25/12/2025');
    });
  });

  group('formatTime', () {
    test('formats time with leading zeros', () {
      expect(DateFormatter.formatTime(DateTime(2026, 1, 1, 9, 5)), '09:05');
    });
  });

  group('isSameDay', () {
    test('returns true for same day', () {
      final a = DateTime(2026, 3, 17, 10, 0);
      final b = DateTime(2026, 3, 17, 23, 59);
      expect(DateFormatter.isSameDay(a, b), true);
    });

    test('returns false for different day', () {
      final a = DateTime(2026, 3, 17);
      final b = DateTime(2026, 3, 18);
      expect(DateFormatter.isSameDay(a, b), false);
    });
  });

  group('isToday', () {
    test('returns true for today', () {
      expect(DateFormatter.isToday(now, now: now), true);
    });
  });

  group('isYesterday', () {
    test('returns true for yesterday', () {
      final yesterday = DateTime(2026, 3, 16, 8, 0);
      expect(DateFormatter.isYesterday(yesterday, now: now), true);
    });

    test('returns false for today', () {
      expect(DateFormatter.isYesterday(now, now: now), false);
    });
  });
}
