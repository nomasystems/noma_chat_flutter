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
}
