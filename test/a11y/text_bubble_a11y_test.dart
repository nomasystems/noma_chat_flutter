import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TextBubble a11y', () {
    testWidgets('renders the message text accessibly', (tester) async {
      await tester.pumpWidget(
        wrap(
          const TextBubble(
            text: 'hello world',
            isOutgoing: false,
            enableSelection: false,
          ),
        ),
      );

      expect(find.textContaining('hello world'), findsOneWidget);
    });

    testWidgets(
      'selection-disabled bubble keeps text reachable for screen reader',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          wrap(
            const TextBubble(
              text: 'screen reader text',
              isOutgoing: true,
              enableSelection: false,
            ),
          ),
        );

        final richText = tester.widgetList<RichText>(find.byType(RichText));
        final hasSemanticText = richText.any(
          (rt) => rt.text.toPlainText().contains('screen reader text'),
        );
        expect(hasSemanticText, isTrue);
        handle.dispose();
      },
    );
  });
}
