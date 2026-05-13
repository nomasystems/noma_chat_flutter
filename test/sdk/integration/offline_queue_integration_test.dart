import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineQueue integration', () {
    test('enqueues send on network failure and processes on retry', () async {
      final queue = OfflineQueue(maxRetries: 3);

      // Simulate network failure → enqueue
      queue.enqueue(
        PendingSendMessage(
          id: 'pending-1',
          roomId: 'room-1',
          text: 'Hello offline',
        ),
      );

      expect(queue.length, 1);
      expect(queue.pending.first, isA<PendingSendMessage>());
      final op = queue.pending.first as PendingSendMessage;
      expect(op.text, 'Hello offline');
      expect(op.roomId, 'room-1');

      // Simulate successful retry
      var processed = false;
      await queue.processQueue((op) async {
        processed = true;
        return true;
      });

      expect(processed, isTrue);
      expect(queue.isEmpty, isTrue);
    });

    test('retries up to maxRetries then drops', () async {
      final queue = OfflineQueue(maxRetries: 2);

      queue.enqueue(
        PendingSendMessage(
          id: 'pending-1',
          roomId: 'room-1',
          text: 'Will fail',
        ),
      );

      // First attempt fails
      await queue.processQueue((op) async => false);
      expect(queue.length, 1);
      expect(queue.pending.first.attempts, 1);

      // Second attempt fails → dropped
      await queue.processQueue((op) async => false);
      expect(queue.isEmpty, isTrue);
    });

    test('processes multiple operations in order', () async {
      final queue = OfflineQueue();
      final processed = <String>[];

      queue.enqueue(
        PendingSendMessage(id: 'p1', roomId: 'room-1', text: 'First'),
      );
      queue.enqueue(
        PendingDeleteMessage(id: 'p2', roomId: 'room-1', messageId: 'msg-1'),
      );
      queue.enqueue(
        PendingSendDirectMessage(id: 'p3', contactUserId: 'user-2', text: 'DM'),
      );

      await queue.processQueue((op) async {
        processed.add(op.id);
        return true;
      });

      expect(processed, ['p1', 'p2', 'p3']);
      expect(queue.isEmpty, isTrue);
    });

    test('enqueues direct message and processes correctly', () async {
      final queue = OfflineQueue(maxRetries: 3);

      queue.enqueue(
        PendingSendDirectMessage(
          id: 'pending-dm-1',
          contactUserId: 'contact-1',
          text: 'Hello DM offline',
        ),
      );

      expect(queue.length, 1);
      expect(queue.pending.first, isA<PendingSendDirectMessage>());
      final op = queue.pending.first as PendingSendDirectMessage;
      expect(op.text, 'Hello DM offline');
      expect(op.contactUserId, 'contact-1');

      var processedType = '';
      await queue.processQueue((op) async {
        processedType = op.runtimeType.toString();
        return true;
      });

      expect(processedType, 'PendingSendDirectMessage');
      expect(queue.isEmpty, isTrue);
    });

    test('stops processing on failure and resumes later', () async {
      final queue = OfflineQueue();
      final processed = <String>[];

      queue.enqueue(PendingSendMessage(id: 'p1', roomId: 'r', text: 'a'));
      queue.enqueue(PendingSendMessage(id: 'p2', roomId: 'r', text: 'b'));

      // First op succeeds, second fails
      await queue.processQueue((op) async {
        processed.add(op.id);
        return op.id == 'p1';
      });

      expect(processed, ['p1', 'p2']);
      expect(queue.length, 1);
      expect(queue.pending.first.id, 'p2');

      // Retry succeeds
      processed.clear();
      await queue.processQueue((op) async {
        processed.add(op.id);
        return true;
      });

      expect(processed, ['p2']);
      expect(queue.isEmpty, isTrue);
    });
  });
}
