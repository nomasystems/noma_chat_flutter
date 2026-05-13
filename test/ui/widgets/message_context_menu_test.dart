import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final msg = ChatMessage(
    id: '1',
    from: 'u1',
    text: 'Hello',
    timestamp: DateTime(2026, 1, 1),
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageContextMenu', () {
    testWidgets('shows outgoing actions including edit and delete', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(MessageContextMenu(message: msg, isOutgoing: true)),
      );
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('hides edit and delete for incoming', (tester) async {
      await tester.pumpWidget(
        wrap(MessageContextMenu(message: msg, isOutgoing: false)),
      );
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('hides copy when message has no text', (tester) async {
      final noTextMsg = ChatMessage(
        id: '2',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        messageType: MessageType.attachment,
        attachmentUrl: 'http://example.com/file.jpg',
      );
      await tester.pumpWidget(
        wrap(MessageContextMenu(message: noTextMsg, isOutgoing: true)),
      );
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('calls onAction callback', (tester) async {
      MessageAction? received;
      await tester.pumpWidget(
        wrap(
          MessageContextMenu(
            message: msg,
            isOutgoing: true,
            onAction: (action) => received = action,
          ),
        ),
      );
      await tester.tap(find.text('Reply'));
      expect(received, MessageAction.reply);
    });

    testWidgets('respects enabledActions filter', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageContextMenu(
            message: msg,
            isOutgoing: true,
            enabledActions: const {MessageAction.copy},
          ),
        ),
      );
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });
  });
}
