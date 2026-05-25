import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('ImageBubble a11y', () {
    testWidgets('without caption announces localized Photo label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ImageBubble(imageUrl: 'https://example.test/cat.png')),
      );

      expect(findSemanticsWithLabel('Photo'), findsOneWidget);
    });

    testWidgets('with caption announces the caption as label', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImageBubble(
            imageUrl: 'https://example.test/cat.png',
            caption: 'Mi gato',
          ),
        ),
      );

      expect(findSemanticsWithLabel('Mi gato'), findsOneWidget);
    });

    testWidgets('marks the bubble as image for assistive tech', (tester) async {
      await tester.pumpWidget(
        wrap(const ImageBubble(imageUrl: 'https://example.test/cat.png')),
      );

      final imageSemantics = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.image == true,
        ),
      );
      expect(imageSemantics, isNotEmpty);
    });
  });
}
