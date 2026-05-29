import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final l10n = ChatTheme.defaults.l10n;

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UnreadDivider', () {
    testWidgets('renders the singular label for one unread message', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadDivider(count: 1)));

      expect(find.text(l10n.newMessages(1)), findsOneWidget);
    });

    testWidgets('renders the plural label for several unread messages', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadDivider(count: 5)));

      expect(find.text(l10n.newMessages(5)), findsOneWidget);
    });

    testWidgets('applies a custom text style override', (tester) async {
      // Use a layout-neutral property (color) so the assertion doesn't
      // depend on the test surface width.
      await tester.pumpWidget(
        wrap(
          const UnreadDivider(
            count: 3,
            textStyle: TextStyle(color: Color(0xFF112233)),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text(l10n.newMessages(3)));
      expect(text.style?.color, const Color(0xFF112233));
    });
  });
}
