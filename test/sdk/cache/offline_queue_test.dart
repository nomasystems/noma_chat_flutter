import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineQueue', () {
    late OfflineQueue queue;

    setUp(() {
      queue = OfflineQueue(maxRetries: 3);
    });

    test('starts empty', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
    });

    test('enqueue adds operations', () {
      queue.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );
      expect(queue.length, 1);
      expect(queue.isNotEmpty, isTrue);
    });

    test('processQueue executes and removes successful operations', () async {
      queue.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );
      queue.enqueue(
        PendingDeleteMessage(id: 'op-2', roomId: 'room-1', messageId: 'msg-1'),
      );

      await queue.processQueue((op) async => true);
      expect(queue.isEmpty, isTrue);
    });

    test('processQueue retries failed operations up to maxRetries', () async {
      var now = DateTime(2024);
      final q = OfflineQueue(maxRetries: 3, clock: () => now);
      q.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );

      var attempts = 0;
      await q.processQueue((op) async {
        attempts++;
        return false;
      });
      expect(attempts, 1);
      expect(q.length, 1);

      now = now.add(const Duration(minutes: 1));
      await q.processQueue((op) async => false);
      now = now.add(const Duration(minutes: 1));
      await q.processQueue((op) async => false);
      expect(q.isEmpty, isTrue);
    });

    test('processQueue succeeds on retry', () async {
      var now = DateTime(2024);
      final q = OfflineQueue(maxRetries: 3, clock: () => now);
      q.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );

      await q.processQueue((op) async => false);
      expect(q.length, 1);

      now = now.add(const Duration(minutes: 1));
      await q.processQueue((op) async => true);
      expect(q.isEmpty, isTrue);
    });

    test('clear empties the queue', () {
      queue.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );
      queue.clear();
      expect(queue.isEmpty, isTrue);
    });

    test('pending returns list of operations', () {
      queue.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'Hello'),
      );
      queue.enqueue(
        PendingEditMessage(
          id: 'op-2',
          roomId: 'room-1',
          messageId: 'msg-1',
          text: 'Updated',
        ),
      );

      final pending = queue.pending;
      expect(pending.length, 2);
      expect(pending[0], isA<PendingSendMessage>());
      expect(pending[1], isA<PendingEditMessage>());
    });

    test('PendingSendDirectMessage stores contact info', () {
      final op = PendingSendDirectMessage(
        id: 'op-1',
        contactUserId: 'contact-1',
        text: 'Hi',
        messageType: MessageType.regular,
      );
      expect(op.contactUserId, 'contact-1');
      expect(op.text, 'Hi');
    });

    test('PendingDeleteReaction stores room and message', () {
      final op = PendingDeleteReaction(
        id: 'op-1',
        roomId: 'room-1',
        messageId: 'msg-1',
      );
      expect(op.roomId, 'room-1');
      expect(op.messageId, 'msg-1');
    });
  });
}
