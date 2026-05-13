import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ReactionBar', () {
    testWidgets('shows reactions with counts', (tester) async {
      await tester.pumpWidget(
        wrap(const ReactionBar(reactions: {'👍': 3, '❤️': 1})),
      );

      expect(find.text('👍 3'), findsOneWidget);
      expect(find.text('❤️ 1'), findsOneWidget);
    });

    testWidgets('calls onReactionTap with emoji when tapped', (tester) async {
      String? tappedEmoji;
      await tester.pumpWidget(
        wrap(
          ReactionBar(
            reactions: const {'👍': 3},
            onReactionTap: (emoji) => tappedEmoji = emoji,
          ),
        ),
      );

      await tester.tap(find.text('👍 3'));
      expect(tappedEmoji, '👍');
    });
  });
}
