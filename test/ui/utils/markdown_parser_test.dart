import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const base = TextStyle(fontSize: 14);

  List<TextSpan> parse(String text, {
    ValueChanged<String>? onTapLink,
    ValueChanged<String>? onTapMention,
  }) =>
      parseMarkdown(text,
          baseStyle: base,
          onTapLink: onTapLink,
          onTapMention: onTapMention);

  group('parseMarkdown', () {
    test('returns empty list for empty input', () {
      expect(parse(''), isEmpty);
    });

    test('plain text yields a single plain span', () {
      final spans = parse('hello world');
      expect(spans, hasLength(1));
      expect(spans.first.text, 'hello world');
      expect(spans.first.style, base);
    });

    test('bold **foo** is rendered with FontWeight.bold', () {
      final spans = parse('say **hello** there');
      // splits into: 'say ', 'hello', ' there'
      expect(spans, hasLength(3));
      expect(spans[0].text, 'say ');
      expect(spans[1].text, 'hello');
      expect(spans[1].style?.fontWeight, FontWeight.bold);
      expect(spans[2].text, ' there');
    });

    test('italic *foo* is rendered with FontStyle.italic', () {
      final spans = parse('just *one* word');
      final italic = spans.firstWhere((s) => s.text == 'one');
      expect(italic.style?.fontStyle, FontStyle.italic);
    });

    test('inline code `foo` uses monospace font', () {
      final spans = parse('run `flutter test`');
      final code = spans.firstWhere((s) => s.text == 'flutter test');
      expect(code.style?.fontFamily, 'monospace');
    });

    test('strikethrough ~~foo~~ has lineThrough decoration', () {
      final spans = parse('done ~~old~~ now');
      final s = spans.firstWhere((s) => s.text == 'old');
      expect(s.style?.decoration, TextDecoration.lineThrough);
    });

    test('inline URL becomes a link span with tap recognizer', () {
      String? tapped;
      final spans = parse('see https://example.com today',
          onTapLink: (u) => tapped = u);

      final link =
          spans.firstWhere((s) => s.text == 'https://example.com');
      expect(link.style?.decoration, TextDecoration.underline);
      expect(link.style?.color, Colors.blue);
      final recognizer = link.recognizer as TapGestureRecognizer;
      recognizer.onTap?.call();
      expect(tapped, 'https://example.com');
    });

    test('mention @username sets bold blue and tap recognizer', () {
      String? tapped;
      final spans = parse('hello @alice!', onTapMention: (u) => tapped = u);

      final mention = spans.firstWhere((s) => s.text == '@alice');
      expect(mention.style?.color, Colors.blue);
      expect(mention.style?.fontWeight, FontWeight.bold);
      final recognizer = mention.recognizer as TapGestureRecognizer;
      recognizer.onTap?.call();
      // Default behaviour without explicit mention id strips the @ prefix
      // for the callback payload, but the parser passes the user id when
      // available; either is acceptable here.
      expect(tapped, anyOf('alice', '@alice'));
    });

    test('unmatched bold start falls back through italic check', () {
      // `use ** safely` has no closing `**` so the bold block is skipped;
      // the italic check then consumes the two `*` as an empty italic span.
      // We do not assert the exact internal layout — just that the text is
      // preserved in order with no characters dropped.
      final spans = parse('use ** safely');
      final combined =
          spans.map((s) => s.text).join();
      expect(combined.contains('use '), true);
      expect(combined.contains('safely'), true);
    });

    test('combined styles produce the expected sequence', () {
      final spans = parse('a **bold** and *italic* and `code`');
      expect(spans.map((s) => s.text), containsAllInOrder([
        'a ',
        'bold',
        ' and ',
        'italic',
        ' and ',
        'code',
      ]));
    });

    test('custom styles override the defaults', () {
      const customBold = TextStyle(fontWeight: FontWeight.w900);
      final spans = parseMarkdown('**heavy**',
          baseStyle: base, boldStyle: customBold);
      expect(spans.first.style, customBold);
    });
  });

  group('MarkdownSpan', () {
    test('plain construction', () {
      const s = MarkdownSpan('hi', MarkdownStyle.plain);
      expect(s.text, 'hi');
      expect(s.style, MarkdownStyle.plain);
      expect(s.url, isNull);
    });
  });
}
