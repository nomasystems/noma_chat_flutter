import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/attachment_upload_cancel_registry.dart';

void main() {
  group('AttachmentUploadCancelRegistry', () {
    late AttachmentUploadCancelRegistry registry;

    setUp(() => registry = AttachmentUploadCancelRegistry());

    test('register hands out a live token and tracks it', () {
      final token = registry.register('t1');
      expect(token.isCancelled, isFalse);
      expect(registry.activeCount, 1);
    });

    test('cancel aborts the token, releases the entry and reports it', () {
      final token = registry.register('t1');

      expect(registry.cancel('t1'), isTrue);
      expect(token.isCancelled, isTrue);
      expect(registry.activeCount, 0);
      // Cancelling twice, or after the upload settled, is a no-op.
      expect(registry.cancel('t1'), isFalse);
    });

    test('drop releases the entry without aborting the upload', () {
      final token = registry.register('t1');

      registry.drop('t1');

      expect(token.isCancelled, isFalse);
      expect(registry.activeCount, 0);
      registry.drop('t1');
    });

    test('cancelAll aborts everything outstanding', () {
      final a = registry.register('t1');
      final b = registry.register('t2');

      registry.cancelAll();

      expect(a.isCancelled, isTrue);
      expect(b.isCancelled, isTrue);
      expect(registry.activeCount, 0);
    });

    group('user-initiated vs teardown', () {
      // Both routes surface the same `CancelledFailure` at the upload's
      // call site, but only the user's X may delete the provisional
      // bubble. Keeping the two apart here is what stops that from
      // depending on the order a teardown happens to run its steps in.
      test('cancel marks the id, and the mark is consumed once', () {
        registry.register('t1');
        registry.cancel('t1');

        expect(registry.consumeUserCancelled('t1'), isTrue);
        expect(registry.consumeUserCancelled('t1'), isFalse);
      });

      test('cancelAll marks nothing, whenever it runs', () {
        registry.register('t1');

        registry.cancelAll();

        expect(registry.consumeUserCancelled('t1'), isFalse);
      });

      test('a settled upload was not user-cancelled', () {
        registry.register('t1');
        registry.drop('t1');

        expect(registry.consumeUserCancelled('t1'), isFalse);
      });

      test('cancelling an id that already settled marks nothing', () {
        registry.register('t1');
        registry.drop('t1');

        expect(registry.cancel('t1'), isFalse);
        expect(registry.consumeUserCancelled('t1'), isFalse);
      });

      test('a reused id starts clean', () {
        registry.register('t1');
        registry.cancel('t1');

        registry.register('t1');

        expect(registry.consumeUserCancelled('t1'), isFalse);
      });
    });
  });
}
