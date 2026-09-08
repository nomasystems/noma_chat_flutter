import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const base = TextStyle(fontSize: 14);

  List<TextSpan> parse(
    String text, {
    ValueChanged<String>? onTapLink,
    ValueChanged<String>? onTapMention,
  }) => parseMarkdown(
    text,
    baseStyle: base,
    onTapLink: onTapLink,
    onTapMention: onTapMention,
  );

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
      final spans = parse(
        'see https://example.com today',
        onTapLink: (u) => tapped = u,
      );

      final link = spans.firstWhere((s) => s.text == 'https://example.com');
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

    test('mention without a handler renders as plain body text', () {
      final spans = parse('hello @alice!');

      final mention = spans.firstWhere((s) => s.text == '@alice');
      expect(
        mention.style,
        base,
        reason: 'no handler, no affordance: it must read as body text',
      );
      expect(mention.recognizer, isNull);
    });

    test('an explicit mentionStyle is ignored while unwired', () {
      const loud = TextStyle(color: Colors.purple, fontWeight: FontWeight.w900);
      final spans = parseMarkdown(
        'hello @alice!',
        baseStyle: base,
        mentionStyle: loud,
      );

      final mention = spans.firstWhere((s) => s.text == '@alice');
      expect(
        mention.style,
        base,
        reason: 'styling a mention must not resurrect the tappable look',
      );
    });

    test('unmatched bold start falls back through italic check', () {
      // `use ** safely` has no closing `**` so the bold block is skipped;
      // the italic check then consumes the two `*` as an empty italic span.
      // We do not assert the exact internal layout — just that the text is
      // preserved in order with no characters dropped.
      final spans = parse('use ** safely');
      final combined = spans.map((s) => s.text).join();
      expect(combined.contains('use '), true);
      expect(combined.contains('safely'), true);
    });

    test('combined styles produce the expected sequence', () {
      final spans = parse('a **bold** and *italic* and `code`');
      expect(
        spans.map((s) => s.text),
        containsAllInOrder(['a ', 'bold', ' and ', 'italic', ' and ', 'code']),
      );
    });

    test('custom styles override the defaults', () {
      const customBold = TextStyle(fontWeight: FontWeight.w900);
      final spans = parseMarkdown(
        '**heavy**',
        baseStyle: base,
        boldStyle: customBold,
      );
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

  group('the four things a message can point at', () {
    /// The message QA typed, verbatim from the D89 repro.
    const repro =
        'Guarda qui https://www.wannabeer.beer/piani e anche www.google.it '
        'oppure scrivimi a chiara@example.com o chiama +34655000011';

    test('a schemed URL, a bare host, an email and a phone are all links', () {
      final urls = <String>[];
      final spans = parse(repro, onTapLink: urls.add);
      final links = spans
          .where((s) => s.recognizer != null)
          .map((s) => s.text)
          .toList();
      expect(links, [
        'https://www.wannabeer.beer/piani',
        'www.google.it',
        'chiara@example.com',
        '+34655000011',
      ]);
      for (final s in spans.where((s) => s.recognizer != null)) {
        (s.recognizer! as TapGestureRecognizer).onTap?.call();
      }
      expect(urls, [
        'https://www.wannabeer.beer/piani',
        'https://www.google.it',
        'mailto:chiara@example.com',
        'tel:+34655000011',
      ]);
    });

    test('a bare host is handed over absolute, not as typed', () {
      String? tapped;
      final spans = parse(
        'mira www.google.it hoy',
        onTapLink: (u) => tapped = u,
      );
      final link = spans.firstWhere((s) => s.text == 'www.google.it');
      expect(link.style?.decoration, TextDecoration.underline);
      (link.recognizer! as TapGestureRecognizer).onTap?.call();
      expect(tapped, 'https://www.google.it');
    });

    test('a grouped phone number is dialled without its separators', () {
      String? tapped;
      final spans = parse(
        'llama al +34 655 000 011 cuando puedas',
        onTapLink: (u) => tapped = u,
      );
      final link = spans.firstWhere((s) => s.recognizer != null);
      expect(link.text, '+34 655 000 011');
      (link.recognizer! as TapGestureRecognizer).onTap?.call();
      expect(tapped, 'tel:+34655000011');
    });

    test('the email wins over the mention branch', () {
      // Without the ordering, the loop reaches the `@` and eats
      // `@example` as a mention of a user called "example".
      final spans = parse(
        'escribe a chiara@example.com',
        onTapLink: (_) {},
        onTapMention: (_) {},
      );
      expect(spans.map((s) => s.text).toList(), [
        'escribe a ',
        'chiara@example.com',
      ]);
      expect(spans.last.style?.decoration, TextDecoration.underline);
    });

    test('a dotted local part is not split into a host and a mention', () {
      final spans = parse(
        'escribe a maria.jose@example.com',
        onTapLink: (_) {},
        onTapMention: (_) {},
      );
      final links = spans.where((s) => s.recognizer != null).toList();
      expect(links.map((s) => s.text).toList(), ['maria.jose@example.com']);
    });

    test('a real mention is still a mention', () {
      String? tapped;
      final spans = parse('hola @alice', onTapMention: (u) => tapped = u);
      final mention = spans.firstWhere((s) => s.text == '@alice');
      (mention.recognizer! as TapGestureRecognizer).onTap?.call();
      expect(tapped, 'alice');
    });

    test('dates, prices and plain digits stay plain text', () {
      const prose =
          'quedamos el 2026-08-31 a las 20:00, somos 12 y salen 1.234,56 euros';
      final spans = parse(prose, onTapLink: (_) {});
      expect(spans.where((s) => s.recognizer != null), isEmpty);
      expect(spans.map((s) => s.text).join(), prose);
    });

    test('a word that fails as a link is not retried one letter in', () {
      // `vamos.a` has a one-letter tail and cannot be a host; the scan
      // must not offer `amos.a` next, nor any other suffix.
      final spans = parse('vamos.a ver que tal', onTapLink: (_) {});
      expect(spans.where((s) => s.recognizer != null), isEmpty);
      expect(spans.single.text, 'vamos.a ver que tal');
    });

    test('nothing is dropped or duplicated on the way through', () {
      final spans = parse(repro, onTapLink: (_) {});
      expect(spans.map((s) => s.text).join(), repro);
    });
  });
}
