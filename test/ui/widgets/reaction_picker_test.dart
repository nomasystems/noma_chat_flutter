import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ReactionPicker', () {
    testWidgets('renders all emojis', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍', '❤️', '😂'],
            onReactionSelected: (_) {},
          ),
        ),
      );

      expect(find.text('👍'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('😂'), findsOneWidget);
    });

    testWidgets('fires onReactionSelected when emoji tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍', '❤️'],
            onReactionSelected: (emoji) => selected = emoji,
          ),
        ),
      );

      await tester.tap(find.text('👍'));
      expect(selected, '👍');
    });

    testWidgets('does not show expand button by default', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPicker(reactions: const ['👍'], onReactionSelected: (_) {}),
        ),
      );

      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('shows expand button when showExpandButton is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍'],
            onReactionSelected: (_) {},
            showExpandButton: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('fires onExpandTap when expand button tapped', (tester) async {
      bool expanded = false;
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍'],
            onReactionSelected: (_) {},
            showExpandButton: true,
            onExpandTap: () => expanded = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      expect(expanded, true);
    });
  });
}
