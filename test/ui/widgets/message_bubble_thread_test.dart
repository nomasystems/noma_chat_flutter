import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage makeMessage({String text = 'Hello'}) {
    return ChatMessage(
      id: 'msg1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: text,
    );
  }

  group('MessageBubble thread features', () {
    testWidgets('shows reply count when replyCount > 0', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            replyCount: 5,
          ),
        ),
      );

      expect(find.text('5 replies'), findsOneWidget);
    });

    testWidgets('does not show reply count when replyCount is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: makeMessage(), isOutgoing: false)),
      );

      expect(find.text('0 replies'), findsNothing);
      expect(find.text('replies'), findsNothing);
    });

    testWidgets('does not show reply count when replyCount is 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            replyCount: 0,
          ),
        ),
      );

      expect(find.text('0 replies'), findsNothing);
    });

    testWidgets('tapping reply count triggers onTapThread', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            replyCount: 3,
            onTapThread: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('3 replies'));
      expect(tapped, true);
    });
  });
}
