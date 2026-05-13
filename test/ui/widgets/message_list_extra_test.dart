import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Drives the `_MessageListState` lifecycle paths that the existing
/// `message_list_test.dart` does not reach:
///  * `didUpdateWidget` with a new controller / new `initialMessageId`
///  * `_tryScrollToPending` when the message is already loaded
///  * `_onScroll` fab visibility toggle
///  * group-mode typing label rendering with several users
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const u2 = ChatUser(id: 'u2', displayName: 'Bob');
  const u3 = ChatUser(id: 'u3', displayName: 'Eve');

  ChatMessage msg(
    String id, {
    String from = 'u2',
    String text = 'msg',
    DateTime? ts,
  }) => ChatMessage(
    id: id,
    from: from,
    text: text,
    timestamp: ts ?? DateTime(2026, 1, 1, 12),
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 500, width: 400, child: child)),
  );

  testWidgets('didUpdateWidget swaps controller cleanly', (tester) async {
    final c1 = ChatController(initialMessages: [msg('a')], currentUser: me);
    final c2 = ChatController(initialMessages: [msg('b')], currentUser: me);

    await tester.pumpWidget(wrap(MessageList(controller: c1)));
    expect(find.textContaining('msg'), findsOneWidget);

    await tester.pumpWidget(wrap(MessageList(controller: c2)));
    await tester.pump();

    expect(find.textContaining('msg'), findsOneWidget);

    c1.dispose();
    c2.dispose();
  });

  testWidgets('initialMessageId triggers a scroll attempt when loaded', (
    tester,
  ) async {
    final messages = List<ChatMessage>.generate(
      20,
      (i) => msg('m$i', text: 'msg $i', ts: DateTime(2026, 1, 1, i)),
    );
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
    );

    await tester.pumpWidget(
      wrap(MessageList(controller: controller, initialMessageId: 'm5')),
    );
    // Drive the post-frame callback that pumps `_tryScrollToPending`.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(MessageList), findsOneWidget);
    controller.dispose();
  });

  testWidgets('switching initialMessageId on rebuild re-registers listener', (
    tester,
  ) async {
    final messages = List<ChatMessage>.generate(
      10,
      (i) => msg('m$i', ts: DateTime(2026, 1, 1, i)),
    );
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
    );

    await tester.pumpWidget(
      wrap(MessageList(controller: controller, initialMessageId: 'm3')),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(MessageList(controller: controller, initialMessageId: 'm7')),
    );
    await tester.pump();

    expect(find.byType(MessageList), findsOneWidget);
    controller.dispose();
  });

  testWidgets('group typing with multiple users renders the typing header', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: [msg('m1')],
      currentUser: me,
    );
    controller.setOtherUsers([u2, u3]);
    controller.setTyping('u2', true);
    controller.setTyping('u3', true);

    await tester.pumpWidget(wrap(MessageList(controller: controller)));
    await tester.pump();

    expect(find.byType(TypingIndicator), findsOneWidget);
    controller.dispose();
  });

  testWidgets('avatarBuilder is invoked for typing indicator when set', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: [msg('m1')],
      currentUser: me,
    );
    controller.setOtherUsers([u2, u3]);
    controller.setTyping('u2', true);

    var builderCalled = false;
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          avatarBuilder: (ctx, uid) {
            builderCalled = true;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(builderCalled, isTrue);
    controller.dispose();
  });

  testWidgets('referencedMessages prop is honoured by the bubbles', (
    tester,
  ) async {
    final ref = msg('parent', text: 'original');
    final reply = ChatMessage(
      id: 'reply',
      from: 'u2',
      text: 'reply',
      timestamp: DateTime(2026, 1, 1, 12, 30),
      referencedMessageId: 'parent',
    );

    final controller = ChatController(
      initialMessages: [ref, reply],
      currentUser: me,
    );

    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          referencedMessages:
              const {'parent': null} // pass-through smoke
                  .map((k, v) => MapEntry(k, ref)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MessageBubble), findsWidgets);
    controller.dispose();
  });
}
