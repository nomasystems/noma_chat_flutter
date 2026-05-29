import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('MessageBubble a11y', () {
    testWidgets('outgoing read message exposes "You: hola, Read" label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'hola',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.read);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(findSemanticsWithLabel('You: hola, Read'), findsOneWidget);
    });

    testWidgets(
      'outgoing delivered message includes Delivered status in label',
      (tester) async {
        final message = fixtureMessage(
          text: 'hello',
          from: fixtureUserMe.id,
        ).copyWith(receipt: ReceiptStatus.delivered);

        await tester.pumpWidget(
          wrap(MessageBubble(message: message, isOutgoing: true)),
        );

        expect(findSemanticsWithLabel('You: hello, Delivered'), findsOneWidget);
      },
    );

    testWidgets('outgoing sent message includes Sent status in label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'ping',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(findSemanticsWithLabel('You: ping, Sent'), findsOneWidget);
    });

    testWidgets('incoming message uses sender name as prefix without status', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'qué tal',
        from: fixtureUserOther.id,
      );

      await tester.pumpWidget(
        wrap(
          MessageBubble(message: message, isOutgoing: false, senderName: 'Bob'),
        ),
      );

      expect(findSemanticsWithLabel('Bob: qué tal'), findsOneWidget);
    });

    testWidgets('deleted outgoing message omits status from semantic label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'oops',
        from: fixtureUserMe.id,
      ).copyWith(isDeleted: true, receipt: ReceiptStatus.read);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(
        findSemanticsWithLabel('You: This message was deleted'),
        findsOneWidget,
      );
    });
  });
}
