import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Deliberately the package's own entry point and nothing under `src/`: this
// file is also the proof that a host outside the package can reach the
// helper at all.
import 'package:noma_chat/noma_chat.dart';

/// The search highlight used to be private to `MessageSearchDelegate`, so a
/// host building a row of its own — a chat list saying WHY a room matched —
/// had to write a second one and keep it in step by hand. These pin the
/// behaviour now that it is part of the package's surface.
void main() {
  const base = TextStyle(fontSize: 14);
  const match = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

  List<String?> textsOf(List<TextSpan> spans) =>
      spans.map((s) => s.text).toList();

  List<String?> markedIn(List<TextSpan> spans) =>
      spans.where((s) => s.style == match).map((s) => s.text).toList();

  test('splits around the match and keeps the text whole', () {
    final spans = chatHighlightSpans(
      'Giulia E2E',
      'giu',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans).join(), 'Giulia E2E');
    expect(markedIn(spans), ['Giu']);
  });

  test('marks every occurrence, not only the first', () {
    final spans = chatHighlightSpans(
      'ana banana',
      'an',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans).join(), 'ana banana');
    expect(markedIn(spans), ['an', 'an', 'an']);
  });

  test('a match at the very start opens no empty span before it', () {
    final spans = chatHighlightSpans(
      'Marco',
      'Marco',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans), ['Marco']);
    expect(markedIn(spans), ['Marco']);
  });

  test('an empty query leaves the text as one plain span', () {
    final spans = chatHighlightSpans(
      'Giulia',
      '',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans), ['Giulia']);
    expect(markedIn(spans), isEmpty);
  });

  test('empty text yields one empty plain span rather than nothing', () {
    final spans = chatHighlightSpans(
      '',
      'giu',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans), ['']);
  });

  test(
    'a query with regex metacharacters is matched literally, not compiled',
    () {
      final spans = chatHighlightSpans(
        'a.b and a(b',
        'a.b',
        baseStyle: base,
        matchStyle: match,
      );

      expect(textsOf(spans).join(), 'a.b and a(b');
      expect(markedIn(spans), [
        'a.b',
      ], reason: 'a dot must mean a dot, not "any character"');
    },
  );

  test('nothing to mark leaves the whole text plain', () {
    final spans = chatHighlightSpans(
      'Giulia',
      'zzz',
      baseStyle: base,
      matchStyle: match,
    );

    expect(textsOf(spans), ['Giulia']);
    expect(markedIn(spans), isEmpty);
  });

  testWidgets('a host paints a row with it using nothing but the package '
      'entry point', (tester) async {
    // Exactly the shape a chat list row telling the reader WHY a room
    // matched would take. If the export ever stops reaching the public
    // surface, this file no longer compiles.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text.rich(
            TextSpan(
              children: chatHighlightSpans(
                'Matched in: Giulia E2E',
                'giulia',
                baseStyle: base,
                matchStyle: match,
              ),
            ),
          ),
        ),
      ),
    );

    final painted = tester.widget<Text>(find.byType(Text)).textSpan!;
    expect(painted.toPlainText(), 'Matched in: Giulia E2E');
    final marked = <String?>[];
    painted.visitChildren((span) {
      if (span is TextSpan && span.style == match) marked.add(span.text);
      return true;
    });
    expect(marked, ['Giulia']);
  });
}
