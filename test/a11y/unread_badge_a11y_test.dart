import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('UnreadBadge a11y', () {
    testWidgets('renders count with localized "unread" suffix as label', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 5)));

      expect(findSemanticsWithLabel('5 unread'), findsOneWidget);
    });

    testWidgets('large count keeps semantic label number as actual count', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 250)));

      expect(findSemanticsWithLabel('250 unread'), findsOneWidget);
    });

    testWidgets('badge with zero count renders nothing', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 0)));

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });
}
