import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/url_detector.dart';

void main() {
  group('extractUrls', () {
    test('extracts single URL', () {
      expect(UrlDetector.extractUrls('Visit https://example.com today'), [
        'https://example.com',
      ]);
    });

    test('extracts multiple URLs', () {
      const text = 'See https://a.com and http://b.com/path';
      expect(UrlDetector.extractUrls(text), [
        'https://a.com',
        'http://b.com/path',
      ]);
    });

    test('returns empty list when no URLs', () {
      expect(UrlDetector.extractUrls('no links here'), isEmpty);
    });

    test('handles URLs with query parameters', () {
      expect(UrlDetector.extractUrls('https://example.com/path?q=1&b=2'), [
        'https://example.com/path?q=1&b=2',
      ]);
    });
  });

  group('hasUrl', () {
    test('returns true when URL present', () {
      expect(UrlDetector.hasUrl('Visit https://example.com'), true);
    });

    test('returns false when no URL', () {
      expect(UrlDetector.hasUrl('plain text'), false);
    });
  });

  group('an email address is not two links', () {
    test('the domain half of an address is not extracted', () {
      expect(UrlDetector.extractUrls('escribe a chiara@example.com'), isEmpty);
    });

    test('nor is a dotted local part', () {
      expect(
        UrlDetector.extractUrls('escribe a maria.jose@example.com'),
        isEmpty,
      );
    });

    test('an @ inside a path does not disqualify the URL', () {
      expect(UrlDetector.extractUrls('mira https://example.com/a@b y ya'), [
        'https://example.com/a@b',
      ]);
    });

    test('a real link in the same sentence still comes through', () {
      expect(UrlDetector.extractUrls('www.google.it o chiara@example.com'), [
        'https://www.google.it',
      ]);
    });
  });

  group('a dotted word is not a link', () {
    const linkified = <String, String>{
      'https://example.com': 'https://example.com',
      'http://example.com/a': 'http://example.com/a',
      'https://informe.pdf': 'https://informe.pdf',
      'www.google.it': 'https://www.google.it',
      'www.informe.pdf': 'https://www.informe.pdf',
      'example.com/informe.pdf': 'https://example.com/informe.pdf',
      'example.com/path?q=1': 'https://example.com/path?q=1',
      'noticias.es': 'https://noticias.es',
      'EXAMPLE.COM': 'https://EXAMPLE.COM',
      'museo.museum/entradas': 'https://museo.museum/entradas',
    };

    const notLinkified = <String>[
      'informe.pdf',
      'foto.jpeg',
      'notas.txt',
      'presentacion.pptx',
      'mundo.esto',
      'ci vediamo in piazza.Domani',
      'museo.museum',
      'ok.io',
      '1.234,56',
    ];

    for (final entry in linkified.entries) {
      test('"${entry.key}" is a link', () {
        expect(UrlDetector.extractUrls('mira ${entry.key} y ya'), [
          entry.value,
        ]);
      });
    }

    for (final candidate in notLinkified) {
      test('"$candidate" is plain text', () {
        expect(UrlDetector.extractUrls('mira $candidate y ya'), isEmpty);
      });
    }

    test('the suffix a host adds is honoured', () {
      expect(UrlDetector.extractUrls('mira museo.museum y ya'), isEmpty);
      UrlDetector.extraTlds.add('museum');
      addTearDown(() => UrlDetector.extraTlds.remove('museum'));
      expect(UrlDetector.extractUrls('mira museo.museum y ya'), [
        'https://museo.museum',
      ]);
    });

    test('a suffix added in mixed case is honoured too', () {
      UrlDetector.extraTlds.add('Museum');
      addTearDown(() => UrlDetector.extraTlds.remove('Museum'));
      expect(UrlDetector.extractUrls('mira museo.museum y ya'), [
        'https://museo.museum',
      ]);
    });
  });

  group('matchAt', () {
    test('answers only for a link that starts exactly there', () {
      const text = 'mira www.google.it hoy';
      expect(UrlDetector.matchAt(text, 0), isNull);
      final hit = UrlDetector.matchAt(text, 5)!;
      expect(hit.text, 'www.google.it');
      expect(hit.url, 'https://www.google.it');
      expect(text.substring(hit.end), ' hoy');
    });

    test('leaves trailing sentence punctuation out of the link', () {
      final hit = UrlDetector.matchAt('https://example.com/a.', 0)!;
      expect(hit.text, 'https://example.com/a');
      expect(hit.end, 21);
    });

    test('agrees with extractUrls on what counts as a link', () {
      for (final candidate in const [
        'https://example.com',
        'www.google.it',
        'example.com/path',
        'ab.io',
        'informe.pdf',
        'noticias.es',
        'chiara@example.com',
        'no',
      ]) {
        expect(
          UrlDetector.matchAt(candidate, 0)?.url,
          UrlDetector.extractUrls(candidate).firstOrNull,
          reason: 'the bubble and the Links list must agree on "$candidate"',
        );
      }
    });
  });
}
