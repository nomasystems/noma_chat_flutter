import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;
  final user = const ChatUser(id: 'u1', displayName: 'Alice');

  ChatMessage makeMsg(String id, {DateTime? timestamp}) => ChatMessage(
    id: id,
    from: 'u1',
    text: 'msg $id',
    timestamp: timestamp ?? DateTime(2026, 1, 1),
  );

  setUp(() {
    controller = ChatController(
      initialMessages: [makeMsg('1'), makeMsg('2')],
      currentUser: user,
    );
  });

  tearDown(() => controller.dispose());

  group('markPending', () {
    test('sets message as pending', () {
      controller.markPending('tmp-1');
      expect(controller.isPending('tmp-1'), true);
    });

    test('notifies listeners', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.markPending('tmp-1');
      expect(notified, true);
    });
  });

  group('isPending', () {
    test('returns true for pending message', () {
      controller.markPending('tmp-1');
      expect(controller.isPending('tmp-1'), true);
    });

    test('returns false for unknown message', () {
      expect(controller.isPending('unknown'), false);
    });

    test('returns false for failed message', () {
      controller.markPending('tmp-1');
      controller.markFailed('tmp-1');
      expect(controller.isPending('tmp-1'), false);
    });
  });

  group('markFailed', () {
    test('sets message as failed', () {
      controller.markPending('tmp-1');
      controller.markFailed('tmp-1');
      expect(controller.isFailed('tmp-1'), true);
    });

    test('notifies listeners', () {
      var notified = false;
      controller.markPending('tmp-1');
      controller.addListener(() => notified = true);
      controller.markFailed('tmp-1');
      expect(notified, true);
    });
  });

  group('isFailed', () {
    test('returns true for failed message', () {
      controller.markFailed('tmp-1');
      expect(controller.isFailed('tmp-1'), true);
    });

    test('returns false for unknown message', () {
      expect(controller.isFailed('unknown'), false);
    });

    test('returns false for pending message', () {
      controller.markPending('tmp-1');
      expect(controller.isFailed('tmp-1'), false);
    });
  });

  group('failedMessageIds', () {
    test('returns set of failed IDs', () {
      controller.markFailed('tmp-1');
      controller.markFailed('tmp-2');
      controller.markPending('tmp-3');
      expect(controller.failedMessageIds, {'tmp-1', 'tmp-2'});
    });

    test('returns empty set when no failures', () {
      controller.markPending('tmp-1');
      expect(controller.failedMessageIds, isEmpty);
    });
  });

  group('confirmSent', () {
    test('replaces temp message with server message and clears pending', () {
      final tempMsg = makeMsg('tmp-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(tempMsg);
      controller.markPending('tmp-1');

      final serverMsg = makeMsg('srv-1', timestamp: DateTime(2026, 1, 3));
      controller.confirmSent('tmp-1', serverMsg);

      expect(controller.isPending('tmp-1'), false);
      expect(controller.messages.any((m) => m.id == 'tmp-1'), false);
      expect(controller.messages.any((m) => m.id == 'srv-1'), true);
    });

    test('rebuilds index so new ID is findable', () {
      final tempMsg = makeMsg('tmp-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(tempMsg);
      controller.markPending('tmp-1');

      final serverMsg = makeMsg('srv-1', timestamp: DateTime(2026, 1, 3));
      controller.confirmSent('tmp-1', serverMsg);

      final updated = ChatMessage(
        id: 'srv-1',
        from: 'u1',
        text: 'edited',
        timestamp: DateTime(2026, 1, 3),
      );
      controller.updateMessage(updated);
      expect(
        controller.messages.firstWhere((m) => m.id == 'srv-1').text,
        'edited',
      );
    });

    test('stores temp-to-server ID mapping', () {
      final tempMsg = makeMsg('tmp-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(tempMsg);
      controller.markPending('tmp-1');

      final serverMsg = makeMsg('srv-1', timestamp: DateTime(2026, 1, 3));
      controller.confirmSent('tmp-1', serverMsg);

      expect(controller.serverIdForTemp('tmp-1'), 'srv-1');
    });

    test('adds server message if temp not found in list', () {
      controller.markPending('tmp-missing');

      final serverMsg = makeMsg('srv-1', timestamp: DateTime(2026, 1, 3));
      controller.confirmSent('tmp-missing', serverMsg);

      expect(controller.messages.any((m) => m.id == 'srv-1'), true);
      expect(controller.isPending('tmp-missing'), false);
    });

    test('deduplicates when event arrives before confirmation', () {
      final tempMsg = makeMsg('tmp-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(tempMsg);
      controller.markPending('tmp-1');
      expect(controller.messages, hasLength(3));

      final serverMsg = makeMsg('srv-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(serverMsg);
      expect(controller.messages, hasLength(4));

      controller.confirmSent('tmp-1', serverMsg);

      expect(controller.messages.where((m) => m.id == 'srv-1'), hasLength(1));
      expect(controller.messages.any((m) => m.id == 'tmp-1'), false);
      expect(controller.isPending('tmp-1'), false);
    });
  });

  group('removePending', () {
    test('removes the temp message entirely', () {
      final tempMsg = makeMsg('tmp-1', timestamp: DateTime(2026, 1, 3));
      controller.addMessage(tempMsg);
      controller.markPending('tmp-1');

      controller.removePending('tmp-1');

      expect(controller.isPending('tmp-1'), false);
      expect(controller.messages.any((m) => m.id == 'tmp-1'), false);
    });

    test('clears pending state even if message not in list', () {
      controller.markPending('tmp-ghost');
      controller.removePending('tmp-ghost');
      expect(controller.isPending('tmp-ghost'), false);
    });
  });

  group('addMessages', () {
    test('batch adds multiple messages with single sort', () {
      final msgs = [
        makeMsg('c', timestamp: DateTime(2026, 1, 4)),
        makeMsg('a', timestamp: DateTime(2026, 1, 2)),
        makeMsg('b', timestamp: DateTime(2026, 1, 3)),
      ];
      controller.addMessages(msgs);
      expect(controller.messages, hasLength(5));

      final ids = controller.messages.map((m) => m.id).toList();
      expect(ids.indexOf('a'), lessThan(ids.indexOf('b')));
      expect(ids.indexOf('b'), lessThan(ids.indexOf('c')));
    });

    test('updates existing messages by ID', () {
      final updated = ChatMessage(
        id: '1',
        from: 'u1',
        text: 'batch-updated',
        timestamp: DateTime(2026, 1, 1),
      );
      controller.addMessages([updated]);
      expect(controller.messages, hasLength(2));
      expect(
        controller.messages.firstWhere((m) => m.id == '1').text,
        'batch-updated',
      );
    });

    test('does nothing for empty list', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.addMessages([]);
      expect(notified, false);
    });

    test('mixes new and existing messages', () {
      final updated = ChatMessage(
        id: '1',
        from: 'u1',
        text: 'updated-text',
        timestamp: DateTime(2026, 1, 1),
      );
      final newMsg = makeMsg('3', timestamp: DateTime(2026, 1, 5));
      controller.addMessages([updated, newMsg]);

      expect(controller.messages, hasLength(3));
      expect(
        controller.messages.firstWhere((m) => m.id == '1').text,
        'updated-text',
      );
      expect(controller.messages.any((m) => m.id == '3'), true);
    });
  });

  group('_indexById', () {
    test('is maintained after addMessage', () {
      controller.addMessage(makeMsg('3', timestamp: DateTime(2026, 1, 5)));
      controller.updateMessage(
        ChatMessage(
          id: '3',
          from: 'u1',
          text: 'found-by-index',
          timestamp: DateTime(2026, 1, 5),
        ),
      );
      expect(
        controller.messages.firstWhere((m) => m.id == '3').text,
        'found-by-index',
      );
    });

    test('is maintained after removeMessage', () {
      controller.removeMessage('1');
      controller.updateMessage(
        ChatMessage(
          id: '2',
          from: 'u1',
          text: 'still-findable',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      expect(
        controller.messages.firstWhere((m) => m.id == '2').text,
        'still-findable',
      );
    });

    test('allows addMessage dedup after remove and re-add', () {
      controller.removeMessage('1');
      expect(controller.messages, hasLength(1));

      controller.addMessage(makeMsg('1', timestamp: DateTime(2026, 1, 10)));
      expect(controller.messages, hasLength(2));

      controller.addMessage(makeMsg('1', timestamp: DateTime(2026, 1, 10)));
      expect(controller.messages, hasLength(2));
    });
  });
}
