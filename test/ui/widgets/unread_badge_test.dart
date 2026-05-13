import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UnreadBadge', () {
    testWidgets('shows count', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 5)));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows max+ when over maxCount', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 150)));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('hidden when count is 0', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 0)));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('hidden when count is negative', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: -1)));
      expect(find.text('-1'), findsNothing);
    });

    testWidgets('respects custom maxCount', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 10, maxCount: 9)));
      expect(find.text('9+'), findsOneWidget);
    });
  });
}
