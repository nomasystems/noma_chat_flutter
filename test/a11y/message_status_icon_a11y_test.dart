import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageStatusIcon a11y', () {
    testWidgets('sent status announces Sent', (tester) async {
      await tester.pumpWidget(
        wrap(const MessageStatusIcon(status: ReceiptStatus.sent)),
      );
      expect(find.bySemanticsLabel('Sent'), findsOneWidget);
    });

    testWidgets('delivered status announces Delivered', (tester) async {
      await tester.pumpWidget(
        wrap(const MessageStatusIcon(status: ReceiptStatus.delivered)),
      );
      expect(find.bySemanticsLabel('Delivered'), findsOneWidget);
    });

    testWidgets('read status announces Read', (tester) async {
      await tester.pumpWidget(
        wrap(const MessageStatusIcon(status: ReceiptStatus.read)),
      );
      expect(find.bySemanticsLabel('Read'), findsOneWidget);
    });
  });
}
