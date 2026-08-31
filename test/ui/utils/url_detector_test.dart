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
