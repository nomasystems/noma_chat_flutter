import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// What a text bubble makes tappable, end to end: the parser decides, but
/// only the bubble can lose it again — `SelectableText.rich` swallows every
/// `TextSpan.recognizer`, so a bubble that keeps selection paints live-
/// looking links that never fire.
void main() {
  const repro =
      'Guarda qui https://www.wannabeer.beer/piani e anche www.google.it '
      'oppure scrivimi a chiara@example.com o chiama +34655000011';

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  /// Every tappable span the bubble ended up rendering, in reading order.
  List<TextSpan> tappableSpans(WidgetTester tester) {
    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final out = <TextSpan>[];
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) out.add(span);
      return true;
    });
    return out;
  }

  testWidgets('the four fragments of the message are all tappable', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      wrap(TextBubble(text: repro, isOutgoing: false, onTapLink: tapped.add)),
    );

    final spans = tappableSpans(tester);
    expect(spans.map((s) => s.text).toList(), [
      'https://www.wannabeer.beer/piani',
      'www.google.it',
      'chiara@example.com',
      '+34655000011',
    ]);

    for (final span in spans) {
      (span.recognizer! as TapGestureRecognizer).onTap?.call();
    }
    expect(tapped, [
      'https://www.wannabeer.beer/piani',
      'https://www.google.it',
      'mailto:chiara@example.com',
      'tel:+34655000011',
    ]);
  });

  testWidgets('a message with no link keeps its selection', (tester) async {
    await tester.pumpWidget(
      wrap(
        TextBubble(
          text: 'quedamos el 31 a las 20:00, somos 12',
          isOutgoing: true,
          onTapLink: (_) {},
        ),
      ),
    );
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
