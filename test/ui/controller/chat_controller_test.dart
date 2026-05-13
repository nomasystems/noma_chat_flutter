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

  group('messages', () {
    test('initial messages are accessible', () {
      expect(controller.messages, hasLength(2));
    });

    test('messages are sorted by timestamp', () {
      final c = ChatController(
        initialMessages: [
          makeMsg('b', timestamp: DateTime(2026, 1, 2)),
          makeMsg('a', timestamp: DateTime(2026, 1, 1)),
        ],
        currentUser: user,
      );
      expect(c.messages.first.id, 'a');
      expect(c.messages.last.id, 'b');
      c.dispose();
    });
  });

  group('addMessage', () {
    test('adds new message and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.addMessage(makeMsg('3'));
      expect(controller.messages, hasLength(3));
      expect(notified, true);
    });

    test('deduplicates by id', () {
      controller.addMessage(makeMsg('1'));
      expect(controller.messages, hasLength(2));
    });

    test('re-sorts when updating existing message with different timestamp', () {
      controller.addMessage(makeMsg('3', timestamp: DateTime(2026, 1, 3)));
      expect(controller.messages.last.id, '3');

      final updated = makeMsg('3', timestamp: DateTime(2025, 12, 1));
      controller.addMessage(updated);
      expect(controller.messages.first.id, '3');
      expect(controller.messages, hasLength(3));
    });
  });

  group('updateMessage', () {
    test('updates existing message', () {
      final updated = ChatMessage(
        id: '1',
        from: 'u1',
        text: 'updated',
        timestamp: DateTime(2026, 1, 1),
      );
      controller.updateMessage(updated);
      expect(controller.messages.first.text, 'updated');
    });

    test('ignores non-existing message', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.updateMessage(makeMsg('999'));
      expect(notified, false);
    });
  });

  group('removeMessage', () {
    test('removes by id', () {
      controller.removeMessage('1');
      expect(controller.messages, hasLength(1));
    });
  });

  group('clearMessages', () {
    test('clears all messages', () {
      controller.clearMessages();
      expect(controller.messages, isEmpty);
    });

    test('clears index so addMessage works after clear', () {
      controller.clearMessages();
      controller.addMessage(makeMsg('1', timestamp: DateTime(2026, 2, 1)));
      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.id, '1');
    });

    test('clears reactions and receipts', () {
      controller.addReaction('1', '👍');
      controller.updateReceipt('1', ReceiptStatus.read);
      controller.clearMessages();
      expect(controller.reactions, isEmpty);
      expect(controller.receiptStatuses, isEmpty);
    });

    test('clears pending state', () {
      controller.markPending('tmp-1');
      controller.clearMessages();
      expect(controller.isPending('tmp-1'), false);
      expect(controller.failedMessageIds, isEmpty);
    });

    test('clears reply and editing state', () {
      controller.setReplyTo(makeMsg('1'));
      controller.clearMessages();
      expect(controller.replyingTo, isNull);
      expect(controller.editingMessage, isNull);
    });

    test('resets pagination state', () {
      controller.setPaginationState(hasMore: false, cursor: 'abc');
      controller.clearMessages();
      expect(controller.hasMoreMessages, true);
      expect(controller.oldestMessageCursor, isNull);
    });
  });

  group('setReplyTo', () {
    test('sets and clears reply', () {
      final msg = makeMsg('1');
      controller.setReplyTo(msg);
      expect(controller.replyingTo, msg);
      controller.setReplyTo(null);
      expect(controller.replyingTo, isNull);
    });
  });

  group('setTyping', () {
    test('adds and removes typing user', () {
      controller.setTyping('u2', true);
      expect(controller.typingUserIds, ['u2']);
      controller.setTyping('u2', false);
      expect(controller.typingUserIds, isEmpty);
    });

    test('does not notify when no change', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.setTyping('u2', false);
      expect(count, 0);
    });
  });

  test('currentUser and otherUsers are accessible', () {
    final c = ChatController(
      initialMessages: [],
      currentUser: user,
      otherUsers: [const ChatUser(id: 'u2')],
    );
    expect(c.currentUser.id, 'u1');
    expect(c.otherUsers, hasLength(1));
    c.dispose();
  });

  group('getMessageById', () {
    test('returns message when it exists', () {
      final msg = controller.getMessageById('1');
      expect(msg, isNotNull);
      expect(msg!.id, '1');
    });

    test('returns null for non-existing id', () {
      expect(controller.getMessageById('nonexistent'), isNull);
    });
  });

  group('highlightMessage', () {
    test('sets highlighted message id', () {
      controller.highlightMessage('1');
      expect(controller.highlightedMessageId, '1');
    });

    test('notifies listeners', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.highlightMessage('1');
      expect(notified, isTrue);
    });
  });
}
