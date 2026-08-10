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

    group('cancellability signal', () {
      // The ring outlives the ability to cancel — it stays up through the
      // poster frame and the send — so the X needs a signal of its own,
      // and one that flips in place: a ring already built has no other
      // reason to rebuild at the moment the bytes land.
      test('is live while the upload is, and flips on drop', () {
        registry.register('t1');
        final cancellable = registry.cancellableFor('t1');

        expect(cancellable, isNotNull);
        expect(cancellable!.value, isTrue);

        registry.drop('t1');

        // Same instance, new value: whoever is already listening sees it.
        expect(identical(registry.cancellableFor('t1'), cancellable), isTrue);
        expect(cancellable.value, isFalse);
      });

      test('flips on cancel and on cancelAll', () {
        registry.register('t1');
        registry.register('t2');
        final a = registry.cancellableFor('t1')!;
        final b = registry.cancellableFor('t2')!;

        registry.cancel('t1');
        expect(a.value, isFalse);
        expect(b.value, isTrue);

        registry.cancelAll();
        expect(b.value, isFalse);
        expect(registry.cancellableFor('t2'), isNull);
      });

      test('is null for an id that never uploaded', () {
        expect(registry.cancellableFor('nope'), isNull);
      });

      test('notifies listeners rather than only changing value', () {
        registry.register('t1');
        var notified = 0;
        registry.cancellableFor('t1')!.addListener(() => notified++);

        registry.drop('t1');

        expect(notified, 1);
      });
    });

    group('retire', () {
      test('releases the signal so the send leaves nothing behind', () {
        registry.register('t1');
        final cancellable = registry.cancellableFor('t1')!;

        registry.retire('t1');

        expect(cancellable.value, isFalse);
        expect(registry.cancellableFor('t1'), isNull);
        expect(registry.activeCount, 0);
      });

      test('drops a user-cancelled mark nobody consumed', () {
        // The X on the first attachment of a draft DM whose materialization
        // then fails: the flow returns before it ever asks
        // `consumeUserCancelled`, so only `retire` can release the mark.
        registry.register('t1');
        registry.cancel('t1');

        registry.retire('t1');

        expect(registry.consumeUserCancelled('t1'), isFalse);
      });

      test('is a no-op for an id that was never registered', () {
        registry.retire('never');
        expect(registry.activeCount, 0);
      });

      test('cancels nothing — the token is the caller\'s to settle', () {
        final token = registry.register('t1');
        registry.drop('t1');

        registry.retire('t1');

        expect(token.isCancelled, isFalse);
      });
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
