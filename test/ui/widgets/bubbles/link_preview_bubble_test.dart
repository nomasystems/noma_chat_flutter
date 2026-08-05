import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('LinkPreviewBubble scheme allowlist', () {
    testWidgets('paints the card for an https URL', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LinkPreviewBubble(
            url: 'https://example.com/page',
            title: 'Example page',
            description: 'A real page.',
          ),
        ),
      );

      expect(find.text('Example page'), findsOneWidget);
      expect(find.text('A real page.'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(
        tester.getSize(find.byType(LinkPreviewBubble)).height,
        greaterThan(0),
      );
    });

    testWidgets('paints the card for a bare domain', (tester) async {
      await tester.pumpWidget(
        wrap(const LinkPreviewBubble(url: 'example.com/page')),
      );

      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('paints nothing for a javascript: URL', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LinkPreviewBubble(
            url: 'javascript:alert(1)',
            title: 'Example page',
            description: 'A real page.',
          ),
        ),
      );

      expect(find.text('Example page'), findsNothing);
      expect(find.text('A real page.'), findsNothing);
      expect(tester.getSize(find.byType(LinkPreviewBubble)).height, 0);
    });

    testWidgets('paints nothing for a host app deep link', (tester) async {
      await tester.pumpWidget(
        wrap(const LinkPreviewBubble(url: 'wb://plan/1', title: 'Google')),
      );

      expect(find.text('Google'), findsNothing);
      expect(tester.getSize(find.byType(LinkPreviewBubble)).height, 0);
    });

    testWidgets('paints nothing for a file: URL', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LinkPreviewBubble(url: 'file:///etc/passwd', title: 'Invoice'),
        ),
      );

      expect(find.text('Invoice'), findsNothing);
      expect(tester.getSize(find.byType(LinkPreviewBubble)).height, 0);
    });

    testWidgets('paints nothing for an empty URL', (tester) async {
      await tester.pumpWidget(
        wrap(const LinkPreviewBubble(url: '', title: 'Untitled')),
      );

      expect(find.text('Untitled'), findsNothing);
      expect(tester.getSize(find.byType(LinkPreviewBubble)).height, 0);
    });
  });
}
