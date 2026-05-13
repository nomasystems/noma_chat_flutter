import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Targets MessageBubble paths not exercised by `message_bubble_test.dart`:
/// pending / failed (with retry) / deleted / forwarded / reply preview /
/// system messages / link tap / long press menu / scroll-to-reference.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  ChatMessage outgoing({
    String text = 'hi',
    MessageType type = MessageType.regular,
    bool isDeleted = false,
    bool isForwarded = false,
    bool isSystem = false,
    String? referencedMessageId,
  }) =>
      ChatMessage(
        id: 'm1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: text,
        messageType: type,
        isDeleted: isDeleted,
        isForwarded: isForwarded,
        isSystem: isSystem,
        referencedMessageId: referencedMessageId,
      );

  testWidgets('isPending shows the clock icon', (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(),
      isOutgoing: true,
      isPending: true,
    )));
    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });

  testWidgets('isFailed shows the error icon and tap calls onRetry',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(),
      isOutgoing: true,
      isFailed: true,
      onRetry: () => retried = true,
    )));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pump();
    expect(retried, true);
  });

  testWidgets('isDeleted renders the "message deleted" placeholder',
      (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(isDeleted: true),
      isOutgoing: true,
    )));
    expect(find.byIcon(Icons.block), findsOneWidget);
  });

  testWidgets('forwarded message wraps in a ForwardedBubble', (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(isForwarded: true),
      isOutgoing: true,
    )));
    expect(find.byType(ForwardedBubble), findsOneWidget);
  });

  testWidgets('reply preview shows the referenced sender', (tester) async {
    final ref = ChatMessage(
      id: 'm0',
      from: 'u2',
      timestamp: DateTime(2026, 1, 1),
      text: 'parent text',
    );
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(referencedMessageId: 'm0', type: MessageType.reply),
      isOutgoing: true,
      referencedMessage: ref,
      referencedSenderName: 'Alice',
    )));
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('system message renders system bubble', (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(text: 'alice joined', isSystem: true),
      isOutgoing: false,
      systemMessageTextResolver: (msg) => 'Alice joined the room',
    )));
    expect(find.text('Alice joined the room'), findsOneWidget);
  });

  testWidgets('reactions row renders when reactions map has entries',
      (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: outgoing(),
      isOutgoing: true,
      reactions: const {'👍': 2, '❤️': 1},
    )));
    expect(find.byType(ReactionBar), findsOneWidget);
  });
}
