import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Sender-run breaking in `MessageList`: a system notice or the
/// "N new messages" separator ends a run of consecutive bubbles, so the
/// first bubble after either one shows its sender name again.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');
  const bob = ChatUser(id: 'u2', displayName: 'Bob');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  ChatMessage msg(
    String id,
    String from, {
    int minute = 0,
    bool isSystem = false,
  }) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: 'msg $id',
    isSystem: isSystem,
  );

  String? senderNameOf(WidgetTester tester, String messageId) {
    final bubbles = tester.widgetList<MessageBubble>(
      find.byType(MessageBubble),
    );
    for (final bubble in bubbles) {
      if (bubble.message.id == messageId) return bubble.senderName;
    }
    fail('no MessageBubble rendered for $messageId');
  }

  Future<ChatController> pumpRoom(
    WidgetTester tester,
    List<ChatMessage> messages, {
    String? unreadBoundaryMessageId,
    int unreadCount = 0,
  }) async {
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [alice, bob],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: true,
          unreadBoundaryMessageId: unreadBoundaryMessageId,
          unreadCount: unreadCount,
        ),
      ),
    );
    return controller;
  }

  group('system notices break the sender run', () {
    testWidgets('the bubble after a system row shows its sender name again', (
      tester,
    ) async {
      await pumpRoom(tester, [
        msg('m1', 'u1', minute: 1),
        msg('s1', 'u1', minute: 2, isSystem: true),
        msg('m2', 'u1', minute: 3),
      ]);

      expect(senderNameOf(tester, 'm2'), 'Alice');
    });

    testWidgets('two adjacent bubbles from one sender still group', (
      tester,
    ) async {
      await pumpRoom(tester, [
        msg('m1', 'u1', minute: 1),
        msg('m2', 'u1', minute: 3),
      ]);

      expect(senderNameOf(tester, 'm1'), 'Alice');
      expect(senderNameOf(tester, 'm2'), isNull);
    });
  });

  group('the unread separator breaks the sender run', () {
    testWidgets('the bubble under the separator shows its sender name again', (
      tester,
    ) async {
      await pumpRoom(
        tester,
        [msg('m1', 'u1', minute: 1), msg('m2', 'u1', minute: 3)],
        unreadBoundaryMessageId: 'm2',
        unreadCount: 1,
      );

      expect(find.byType(UnreadDivider), findsOneWidget);
      expect(senderNameOf(tester, 'm2'), 'Alice');
    });

    testWidgets('a boundary with a zero count draws nothing and groups', (
      tester,
    ) async {
      await pumpRoom(tester, [
        msg('m1', 'u1', minute: 1),
        msg('m2', 'u1', minute: 3),
      ], unreadBoundaryMessageId: 'm2');

      expect(find.byType(UnreadDivider), findsNothing);
      expect(senderNameOf(tester, 'm2'), isNull);
    });
  });
}
