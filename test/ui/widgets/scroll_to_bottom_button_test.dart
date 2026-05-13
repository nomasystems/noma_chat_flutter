import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ScrollToBottomButton', () {
    testWidgets('hidden when visible is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: false,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shown when visible is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows unread badge when count > 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: true,
              onPressed: () {},
              unreadCount: 5,
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: true,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      expect(pressed, true);
    });

    testWidgets('shows down arrow icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('has Semantics label for scroll to bottom', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(
              visible: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Scroll to bottom',
        ),
        findsOneWidget,
      );
    });
  });
}
