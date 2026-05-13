import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

  final parentMessage = ChatMessage(
    id: 'parent1',
    from: 'u2',
    timestamp: DateTime(2026, 1, 1),
    text: 'Parent message',
  );

  final reply1 = ChatMessage(
    id: 'reply1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 0, 1),
    text: 'First reply',
  );

  final reply2 = ChatMessage(
    id: 'reply2',
    from: 'u2',
    timestamp: DateTime(2026, 1, 1, 0, 2),
    text: 'Second reply',
  );

  group('ThreadView', () {
    testWidgets('renders parent message and replies', (tester) async {
      final controller = ChatController(
        initialMessages: [reply1, reply2],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.textContaining('Parent message'), findsOneWidget);
      expect(find.textContaining('First reply'), findsOneWidget);
      expect(find.textContaining('Second reply'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('shows thread header with title', (tester) async {
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.text('Thread'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('shows reply count in header', (tester) async {
      final controller = ChatController(
        initialMessages: [reply1, reply2],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            replies: [reply1, reply2],
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.text('2 replies'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('send reply triggers callback', (tester) async {
      String? sentText;
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            onSendReply: (text) => sentText = text,
            currentUserId: 'u1',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'My reply');
      await tester.pump();

      final sendButton = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.child is Container,
      );
      await tester.tap(sendButton.last);
      await tester.pump();

      expect(sentText, 'My reply');

      controller.dispose();
    });

    testWidgets('close button triggers onClose', (tester) async {
      var closed = false;
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            onClose: () => closed = true,
            currentUserId: 'u1',
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, true);

      controller.dispose();
    });
  });
}
