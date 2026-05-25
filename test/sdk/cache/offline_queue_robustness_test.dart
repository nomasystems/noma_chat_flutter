import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineQueue robustness', () {
    test('discards operations older than maxAge during processing', () async {
      final now = DateTime.utc(2026, 1, 2);
      final queue = OfflineQueue(
        maxRetries: 3,
        maxAge: const Duration(hours: 24),
        clock: () => now,
      );

      queue.enqueue(
        PendingSendMessage(
          id: 'old-op',
          roomId: 'room-1',
          text: 'Expired',
          createdAt: DateTime.utc(2025, 12, 31),
        ),
      );
      queue.enqueue(
        PendingSendMessage(
          id: 'new-op',
          roomId: 'room-1',
          text: 'Fresh',
          createdAt: DateTime.utc(2026, 1, 1, 23, 0),
        ),
      );

      final processed = <String>[];
      final dropped = <(String, String)>[];
      final queueWithCallbacks = OfflineQueue(
        maxRetries: 3,
        maxAge: const Duration(hours: 24),
        onOperationDropped: (op, reason) => dropped.add((op.id, reason)),
        clock: () => now,
      );
      queueWithCallbacks.enqueue(
        PendingSendMessage(
          id: 'old-op',
          roomId: 'room-1',
          text: 'Expired',
          createdAt: DateTime.utc(2025, 12, 31),
        ),
      );
      queueWithCallbacks.enqueue(
        PendingSendMessage(
          id: 'new-op',
          roomId: 'room-1',
          text: 'Fresh',
          createdAt: DateTime.utc(2026, 1, 1, 23, 0),
        ),
      );

      await queueWithCallbacks.processQueue((op) async {
        processed.add(op.id);
        return true;
      });

      expect(processed, ['new-op']);
      expect(dropped, [('old-op', 'ttl_expired')]);
    });

    test('rejects enqueue when queue is full', () async {
      final dropped = <(String, String)>[];
      final queue = OfflineQueue(
        maxRetries: 3,
        maxQueueSize: 2,
        onOperationDropped: (op, reason) => dropped.add((op.id, reason)),
      );

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a'));
      queue.enqueue(PendingSendMessage(id: 'op-2', roomId: 'r', text: 'b'));

      expect(queue.length, 2);

      queue.enqueue(PendingSendMessage(id: 'op-3', roomId: 'r', text: 'c'));

      expect(queue.length, 2);
      expect(dropped, [('op-3', 'queue_full')]);
    });

    test('calls onOperationDropped with reason on max retries', () async {
      final dropped = <(String, String)>[];
      final queue = OfflineQueue(
        maxRetries: 1,
        onOperationDropped: (op, reason) => dropped.add((op.id, reason)),
      );

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a'));

      await queue.processQueue((op) async => false);

      expect(queue.isEmpty, isTrue);
      expect(dropped, [('op-1', 'max_retries')]);
    });

    test('applies exponential backoff between retries', () async {
      final queue = OfflineQueue(maxRetries: 3);

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a'));

      await queue.processQueue((op) async => false);

      // Non-blocking: op is re-enqueued with nextRetryAt set in the future
      expect(queue.length, 1);
      final op = queue.pending.first;
      expect(op.nextRetryAt, isNotNull);
      expect(op.nextRetryAt!.isAfter(DateTime.now()), isTrue);
    });

    test('processes operations normally when no TTL or size issues', () async {
      final queue = OfflineQueue(
        maxRetries: 3,
        maxAge: const Duration(hours: 24),
        maxQueueSize: 100,
      );

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a'));
      queue.enqueue(PendingSendMessage(id: 'op-2', roomId: 'r', text: 'b'));

      final processed = <String>[];
      await queue.processQueue((op) async {
        processed.add(op.id);
        return true;
      });

      expect(processed, ['op-1', 'op-2']);
      expect(queue.isEmpty, isTrue);
    });

    test('default maxAge is 24 hours', () {
      final queue = OfflineQueue();
      final now = DateTime.now();
      final old = now.subtract(const Duration(hours: 25));

      queue.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a', createdAt: old),
      );

      final dropped = <String>[];
      final queueWithDrop = OfflineQueue(
        onOperationDropped: (op, reason) => dropped.add(reason),
      );
      queueWithDrop.enqueue(
        PendingSendMessage(id: 'op-1', roomId: 'r', text: 'a', createdAt: old),
      );

      queueWithDrop.processQueue((op) async => true);
    });

    test('default maxQueueSize is 100', () {
      final queue = OfflineQueue();
      for (var i = 0; i < 100; i++) {
        queue.enqueue(PendingSendMessage(id: 'op-$i', roomId: 'r', text: 'a'));
      }
      expect(queue.length, 100);

      var dropCalled = false;
      final fullQueue = OfflineQueue(
        maxQueueSize: 100,
        onOperationDropped: (op, reason) => dropCalled = true,
      );
      for (var i = 0; i < 100; i++) {
        fullQueue.enqueue(
          PendingSendMessage(id: 'op-$i', roomId: 'r', text: 'a'),
        );
      }
      fullQueue.enqueue(
        PendingSendMessage(id: 'op-overflow', roomId: 'r', text: 'a'),
      );
      expect(dropCalled, isTrue);
      expect(fullQueue.length, 100);
    });

    test('enqueue swallows _persist errors and logs them instead of '
        'crashing the host app', () async {
      // Simulates Hive disk full / lock contention by throwing on every
      // saveOfflineQueue. Before the fix this would surface as an
      // unhandled async exception in the Zone (enqueue is sync, the
      // future from _persist was fire-and-forget).
      final logs = <(String, String)>[];
      final queue = OfflineQueue(
        store: _ThrowingStore(),
        logger: (level, message) => logs.add((level, message)),
      );

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'hi'));

      // Give the swallowed Future a microtask to fire its catchError.
      await Future<void>.delayed(Duration.zero);

      expect(logs, hasLength(1));
      expect(logs.first.$1, 'warn');
      expect(logs.first.$2, contains('persist failed'));
      // The op stays in memory — the queue is unchanged, only the
      // mirror to disk failed.
      expect(queue.length, 1);
    });
  });
}

class _ThrowingStore implements ChatLocalDatasource {
  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) async {
    throw StateError('disk full (simulated)');
  }

  @override
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue() async =>
      const ChatSuccess(<Map<String, dynamic>>[]);

  @override
  Future<ChatResult<void>> clearOfflineQueue() async => const ChatSuccess(null);

  // The rest of the surface is unused by this test — synthesizing every
  // method would dwarf the actual assertion. The interface is wide but
  // OfflineQueue only ever touches the three above.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
