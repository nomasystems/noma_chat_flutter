import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TypingIndicator', () {
    testWidgets('renders 3 dots', (tester) async {
      await tester.pumpWidget(wrap(const TypingIndicator()));

      final dots = find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).shape == BoxShape.circle);
      expect(dots, findsNWidgets(3));
    });

    testWidgets('has Semantics liveRegion', (tester) async {
      await tester.pumpWidget(wrap(const TypingIndicator()));

      final semantics = tester.widget<Semantics>(find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ));
      expect(semantics.properties.label, 'Typing');
    });
  });
}
