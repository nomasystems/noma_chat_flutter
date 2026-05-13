import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TextBubble', () {
    testWidgets('renders text', (tester) async {
      await tester.pumpWidget(
        wrap(const TextBubble(text: 'Hello', isOutgoing: true)),
      );
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows timestamp when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          TextBubble(
            text: 'Hello',
            isOutgoing: false,
            timestamp: DateTime(2026, 1, 1, 14, 30),
          ),
        ),
      );
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('shows edited label when isEdited=true', (tester) async {
      await tester.pumpWidget(
        wrap(const TextBubble(text: 'Hello', isOutgoing: true, isEdited: true)),
      );
      expect(find.text('edited'), findsOneWidget);
    });

    testWidgets('uses SelectableText when enableSelection=true',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const TextBubble(
            text: 'Hello',
            isOutgoing: true,
            enableSelection: true,
          ),
        ),
      );
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('uses Text when enableSelection=false', (tester) async {
      await tester.pumpWidget(
        wrap(
          const TextBubble(
            text: 'Hello',
            isOutgoing: true,
            enableSelection: false,
          ),
        ),
      );
      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });
}
