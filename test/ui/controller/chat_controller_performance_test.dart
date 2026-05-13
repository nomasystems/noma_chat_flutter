import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final user = const ChatUser(id: 'u1', displayName: 'Alice');

  ChatMessage makeMsg(String id, {DateTime? timestamp}) => ChatMessage(
        id: id,
        from: 'u1',
        text: 'msg $id',
        timestamp: timestamp ?? DateTime(2026, 1, 1),
      );

  group('bounded message list', () {
    test('trims oldest messages when exceeding maxMessages', () {
      final controller = ChatController(
        initialMessages: [],
        currentUser: user,
      );

      final messages = List.generate(
        ChatController.maxMessages + 50,
        (i) => makeMsg(
          'msg-$i',
          timestamp: DateTime(2026, 1, 1, 0, 0, i),
        ),
      );
      controller.addMessages(messages);

      expect(controller.messages.length, ChatController.maxMessages);
      expect(controller.hasMoreMessages, true);
      expect(controller.messages.first.id, 'msg-50');
      expect(controller.messages.last.id, 'msg-549');

      controller.dispose();
    });

    test('does not trim when at or below maxMessages', () {
      final controller = ChatController(
        initialMessages: [],
        currentUser: user,
      );

      final messages = List.generate(
        ChatController.maxMessages,
        (i) => makeMsg(
          'msg-$i',
          timestamp: DateTime(2026, 1, 1, 0, 0, i),
        ),
      );
      controller.addMessages(messages);

      expect(controller.messages.length, ChatController.maxMessages);
      expect(controller.messages.first.id, 'msg-0');

      controller.dispose();
    });

    test('trims on addMessage when exceeding maxMessages', () {
      final controller = ChatController(
        initialMessages: [],
        currentUser: user,
      );

      final messages = List.generate(
        ChatController.maxMessages,
        (i) => makeMsg(
          'msg-$i',
          timestamp: DateTime(2026, 1, 1, 0, 0, i),
        ),
      );
      controller.addMessages(messages);

      controller.addMessage(makeMsg(
        'new-msg',
        timestamp: DateTime(2026, 1, 1, 1, 0, 0),
      ));

      expect(controller.messages.length, ChatController.maxMessages);
      expect(controller.hasMoreMessages, true);
      expect(controller.messages.last.id, 'new-msg');
      expect(controller.messages.first.id, 'msg-1');

      controller.dispose();
    });

    test('sets hasMoreMessages to true after trimming', () {
      final controller = ChatController(
        initialMessages: [],
        currentUser: user,
      );
      controller.setPaginationState(hasMore: false);
      expect(controller.hasMoreMessages, false);

      final messages = List.generate(
        ChatController.maxMessages + 10,
        (i) => makeMsg(
          'msg-$i',
          timestamp: DateTime(2026, 1, 1, 0, 0, i),
        ),
      );
      controller.addMessages(messages);

      expect(controller.hasMoreMessages, true);

      controller.dispose();
    });
  });

  group('typing auto-timeout', () {
    test('typing clears after timeout', () {
      fakeAsync((async) {
        final controller = ChatController(
          initialMessages: [],
          currentUser: user,
        );

        controller.setTyping('u2', true);
        expect(controller.typingUserIds, ['u2']);

        async.elapse(controller.typingTimeout);

        expect(controller.typingUserIds, isEmpty);

        controller.dispose();
      });
    });

    test('explicit stop cancels timer', () {
      fakeAsync((async) {
        final controller = ChatController(
          initialMessages: [],
          currentUser: user,
        );

        controller.setTyping('u2', true);
        expect(controller.typingUserIds, ['u2']);

        async.elapse(const Duration(seconds: 10));
        controller.setTyping('u2', false);
        expect(controller.typingUserIds, isEmpty);

        async.elapse(const Duration(seconds: 30));
        expect(controller.typingUserIds, isEmpty);

        controller.dispose();
      });
    });

    test('new typing event resets timer', () {
      fakeAsync((async) {
        final controller = ChatController(
          initialMessages: [],
          currentUser: user,
          typingTimeout: const Duration(seconds: 30),
        );

        controller.setTyping('u2', true);
        async.elapse(const Duration(seconds: 20));
        expect(controller.typingUserIds, ['u2']);

        controller.setTyping('u2', true);

        async.elapse(const Duration(seconds: 20));
        expect(controller.typingUserIds, ['u2']);

        async.elapse(const Duration(seconds: 15));
        expect(controller.typingUserIds, isEmpty);

        controller.dispose();
      });
    });

    test('multiple users have independent timers', () {
      fakeAsync((async) {
        final controller = ChatController(
          initialMessages: [],
          currentUser: user,
          typingTimeout: const Duration(seconds: 25),
        );

        controller.setTyping('u2', true);
        async.elapse(const Duration(seconds: 10));
        controller.setTyping('u3', true);

        async.elapse(const Duration(seconds: 20));
        expect(controller.typingUserIds, contains('u3'));
        expect(controller.typingUserIds, isNot(contains('u2')));

        async.elapse(const Duration(seconds: 15));
        expect(controller.typingUserIds, isEmpty);

        controller.dispose();
      });
    });
  });
}
