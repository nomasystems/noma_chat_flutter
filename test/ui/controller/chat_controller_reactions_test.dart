import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: [],
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
    );
  });

  tearDown(() => controller.dispose());

  group('reactions', () {
    test('addReaction creates entry and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.addReaction('msg1', '👍');
      expect(controller.reactions['msg1'], {'👍': 1});
      expect(notified, true);
    });

    test('addReaction increments count', () {
      controller.addReaction('msg1', '👍');
      controller.addReaction('msg1', '👍');
      expect(controller.reactions['msg1']!['👍'], 2);
    });

    test('removeReaction decrements count', () {
      controller.addReaction('msg1', '👍');
      controller.addReaction('msg1', '👍');
      controller.removeReaction('msg1', '👍');
      expect(controller.reactions['msg1']!['👍'], 1);
    });

    test('removeReaction removes emoji when count reaches zero', () {
      controller.addReaction('msg1', '👍');
      controller.removeReaction('msg1', '👍');
      expect(controller.reactions['msg1'], isNull);
    });

    test('clearReactions removes all for message', () {
      controller.addReaction('msg1', '👍');
      controller.addReaction('msg1', '❤️');
      controller.clearReactions('msg1');
      expect(controller.reactions.containsKey('msg1'), false);
    });

    test('setReactions replaces reactions for message', () {
      controller.setReactions('msg1', {'👍': 3, '❤️': 1});
      expect(controller.reactions['msg1'], {'👍': 3, '❤️': 1});
    });
  });

  group('receipts', () {
    test('updateReceipt stores status and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.updateReceipt('msg1', ReceiptStatus.delivered);
      expect(controller.receiptStatuses['msg1'], ReceiptStatus.delivered);
      expect(notified, true);
    });

    test('updateReceipt overwrites previous status', () {
      controller.updateReceipt('msg1', ReceiptStatus.sent);
      controller.updateReceipt('msg1', ReceiptStatus.read);
      expect(controller.receiptStatuses['msg1'], ReceiptStatus.read);
    });
  });

  group('pagination', () {
    test('initial state has more messages', () {
      expect(controller.hasMoreMessages, true);
      expect(controller.isLoadingMore, false);
      expect(controller.oldestMessageCursor, isNull);
    });

    test('setPaginationState updates cursor and hasMore', () {
      controller.setPaginationState(hasMore: false, cursor: 'msg-50');
      expect(controller.hasMoreMessages, false);
      expect(controller.oldestMessageCursor, 'msg-50');
    });

    test('setLoadingMore notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setLoadingMore(true);
      expect(controller.isLoadingMore, true);
      expect(notified, true);
    });
  });

  group('setMessages', () {
    test('replaces all messages', () {
      controller.addMessage(ChatMessage(
        id: 'old',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'old',
      ));

      controller.setMessages([
        ChatMessage(
          id: 'new1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 2),
          text: 'new1',
        ),
        ChatMessage(
          id: 'new2',
          from: 'u2',
          timestamp: DateTime(2026, 1, 3),
          text: 'new2',
        ),
      ]);

      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.id, 'new1');
    });
  });
}
