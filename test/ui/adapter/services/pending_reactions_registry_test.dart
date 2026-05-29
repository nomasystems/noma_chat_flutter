import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/pending_reactions_registry.dart';

void main() {
  group('PendingReactionsRegistry', () {
    late PendingReactionsRegistry registry;

    setUp(() => registry = PendingReactionsRegistry());

    test('starts empty', () {
      expect(registry.isPendingDelete('m1'), isFalse);
      expect(registry.length, 0);
    });

    test('mark then query returns true', () {
      registry.markPendingDelete('m1');
      expect(registry.isPendingDelete('m1'), isTrue);
      expect(registry.length, 1);
    });

    test('unmark removes the entry', () {
      registry.markPendingDelete('m1');
      registry.unmarkPendingDelete('m1');
      expect(registry.isPendingDelete('m1'), isFalse);
      expect(registry.length, 0);
    });

    test('mark is idempotent — double-mark same id stays at length 1', () {
      registry.markPendingDelete('m1');
      registry.markPendingDelete('m1');
      expect(registry.length, 1);
    });

    test('unmark on unmarked id is a no-op', () {
      registry.unmarkPendingDelete('never-marked');
      expect(registry.length, 0);
    });

    test('clear drops all pending entries', () {
      registry
        ..markPendingDelete('m1')
        ..markPendingDelete('m2')
        ..markPendingDelete('m3');
      expect(registry.length, 3);
      registry.clear();
      expect(registry.length, 0);
      expect(registry.isPendingDelete('m1'), isFalse);
    });

    test('different message ids are tracked independently', () {
      registry.markPendingDelete('m1');
      expect(registry.isPendingDelete('m1'), isTrue);
      expect(registry.isPendingDelete('m2'), isFalse);
      registry.markPendingDelete('m2');
      registry.unmarkPendingDelete('m1');
      expect(registry.isPendingDelete('m1'), isFalse);
      expect(registry.isPendingDelete('m2'), isTrue);
    });
  });
}
