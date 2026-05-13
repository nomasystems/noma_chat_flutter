import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('DateSeparator', () {
    testWidgets('renders formatted date text', (tester) async {
      final date = DateTime(2025, 3, 15);
      await tester.pumpWidget(wrap(DateSeparator(date: date)));

      expect(find.text('15/03/2025'), findsOneWidget);
    });

    testWidgets('has Semantics wrapper', (tester) async {
      final date = DateTime(2025, 3, 15);
      await tester.pumpWidget(wrap(DateSeparator(date: date)));

      final semantics = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '15/03/2025',
      );
      expect(semantics, findsOneWidget);
    });
  });
}
