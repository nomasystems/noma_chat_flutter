import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageStatusIcon', () {
    testWidgets('renders for sent', (tester) async {
      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.sent),
      ));
      expect(find.byType(MessageStatusIcon), findsOneWidget);
    });

    testWidgets('renders for delivered', (tester) async {
      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.delivered),
      ));
      expect(find.byType(MessageStatusIcon), findsOneWidget);
    });

    testWidgets('renders for read', (tester) async {
      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.read),
      ));
      expect(find.byType(MessageStatusIcon), findsOneWidget);
    });

    testWidgets('sent has narrower width than delivered', (tester) async {
      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.sent, size: 16),
      ));
      final sentBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.delivered, size: 16),
      ));
      final deliveredBox =
          tester.widget<SizedBox>(find.byType(SizedBox).first);

      expect(sentBox.width! < deliveredBox.width!, isTrue);
    });

    testWidgets('has Semantics labels', (tester) async {
      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.sent),
      ));
      expect(find.bySemanticsLabel('Sent'), findsOneWidget);

      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.delivered),
      ));
      expect(find.bySemanticsLabel('Delivered'), findsOneWidget);

      await tester.pumpWidget(wrap(
        const MessageStatusIcon(status: ReceiptStatus.read),
      ));
      expect(find.bySemanticsLabel('Read'), findsOneWidget);
    });
  });
}
