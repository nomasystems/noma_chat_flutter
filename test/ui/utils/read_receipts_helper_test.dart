import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('readersFor', () {
    final message = ChatMessage(
      id: 'm1',
      from: 'alice',
      timestamp: DateTime(2026, 5, 12, 10, 0, 0),
      text: 'hello',
    );

    test('returns empty when receipts list is empty', () {
      expect(readersFor(message, const []), isEmpty);
    });

    test('excludes the message author', () {
      final receipts = [
        ReadReceipt(
          userId: 'alice',
          lastReadAt: DateTime(2026, 5, 12, 11, 0, 0),
        ),
      ];
      expect(readersFor(message, receipts), isEmpty);
    });

    test('excludes users with null lastReadAt', () {
      final receipts = [const ReadReceipt(userId: 'bob', lastReadAt: null)];
      expect(readersFor(message, receipts), isEmpty);
    });

    test('excludes users whose lastReadAt is before the message timestamp', () {
      final receipts = [
        ReadReceipt(
          userId: 'bob',
          lastReadAt: DateTime(2026, 5, 12, 9, 59, 59),
        ),
      ];
      expect(readersFor(message, receipts), isEmpty);
    });

    test('includes users whose lastReadAt equals the message timestamp', () {
      final receipts = [
        ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 5, 12, 10, 0, 0)),
      ];
      expect(readersFor(message, receipts), ['bob']);
    });

    test('includes users whose lastReadAt is after the message timestamp', () {
      final receipts = [
        ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 5, 12, 10, 5, 0)),
        ReadReceipt(
          userId: 'carol',
          lastReadAt: DateTime(2026, 5, 12, 10, 10, 0),
        ),
      ];
      expect(readersFor(message, receipts), ['bob', 'carol']);
    });

    test('mixed: filters out author, nulls and before-timestamp', () {
      final receipts = [
        ReadReceipt(
          userId: 'alice',
          lastReadAt: DateTime(2026, 5, 12, 11, 0, 0),
        ),
        const ReadReceipt(userId: 'bob', lastReadAt: null),
        ReadReceipt(
          userId: 'carol',
          lastReadAt: DateTime(2026, 5, 12, 9, 0, 0),
        ),
        ReadReceipt(
          userId: 'dave',
          lastReadAt: DateTime(2026, 5, 12, 10, 30, 0),
        ),
      ];
      expect(readersFor(message, receipts), ['dave']);
    });
  });
}
