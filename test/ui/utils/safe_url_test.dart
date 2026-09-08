import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/safe_url.dart';

void main() {
  group('webUrlOrNull accepts web URLs', () {
    test('keeps an https URL verbatim', () {
      expect(
        webUrlOrNull('https://example.com/a?b=1#c').toString(),
        'https://example.com/a?b=1#c',
      );
    });

    test('keeps an http URL verbatim', () {
      expect(
        webUrlOrNull('http://example.com/x').toString(),
        'http://example.com/x',
      );
    });

    test('reads a bare domain as https', () {
      expect(
        webUrlOrNull('example.com/path').toString(),
        'https://example.com/path',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        webUrlOrNull('  https://example.com  ').toString(),
        'https://example.com',
      );
    });

    test('normalizes an upper-case scheme', () {
      expect(webUrlOrNull('HTTPS://EXAMPLE.COM')?.scheme, 'https');
    });
  });

  group('webUrlOrNull rejects everything else', () {
    test('rejects javascript:', () {
      expect(webUrlOrNull('javascript:alert(1)'), isNull);
    });

    test('rejects file:', () {
      expect(webUrlOrNull('file:///etc/passwd'), isNull);
    });

    test('rejects intent:', () {
      expect(webUrlOrNull('intent://scan/#Intent;scheme=zxing;end'), isNull);
    });

    test('rejects a host app deep link', () {
      expect(webUrlOrNull('wb://plan/1'), isNull);
    });

    test('rejects mailto: and tel:', () {
      expect(webUrlOrNull('mailto:someone@example.com'), isNull);
      expect(webUrlOrNull('tel:+34600000000'), isNull);
    });

    test('rejects a data: payload', () {
      expect(webUrlOrNull('data:text/plain,hello'), isNull);
    });

    test('rejects null, empty and whitespace-only input', () {
      expect(webUrlOrNull(null), isNull);
      expect(webUrlOrNull(''), isNull);
      expect(webUrlOrNull('   '), isNull);
    });

    test('rejects a web scheme with no host', () {
      expect(webUrlOrNull('https://'), isNull);
      expect(webUrlOrNull('http:///path'), isNull);
    });
  });

  group('launchableUrlOrNull adds mail and phone, and nothing else', () {
    test('accepts a mailto: with a real address', () {
      expect(
        launchableUrlOrNull('mailto:chiara@example.com').toString(),
        'mailto:chiara@example.com',
      );
    });

    test('accepts a tel: with a real number', () {
      expect(
        launchableUrlOrNull('tel:+34655000011').toString(),
        'tel:+34655000011',
      );
    });

    test('still accepts everything webUrlOrNull accepts', () {
      expect(
        launchableUrlOrNull('https://example.com/a?b=1').toString(),
        'https://example.com/a?b=1',
      );
      expect(
        launchableUrlOrNull('example.com/path').toString(),
        'https://example.com/path',
      );
    });

    test('rejects a mailto: carrying anything but an address', () {
      expect(launchableUrlOrNull('mailto:javascript:alert(1)'), isNull);
      expect(launchableUrlOrNull('mailto:'), isNull);
      expect(launchableUrlOrNull('mailto:not-an-address'), isNull);
    });

    test('rejects a tel: carrying anything but a number', () {
      expect(launchableUrlOrNull('tel:;phone-context=evil'), isNull);
      expect(launchableUrlOrNull('tel:'), isNull);
      expect(launchableUrlOrNull('tel:drop table'), isNull);
    });

    test('rejects every scheme outside the allowlist, as before', () {
      expect(launchableUrlOrNull('javascript:alert(1)'), isNull);
      expect(launchableUrlOrNull('file:///etc/passwd'), isNull);
      expect(
        launchableUrlOrNull('intent://scan/#Intent;scheme=zxing;end'),
        isNull,
      );
      expect(launchableUrlOrNull('wb://plan/1'), isNull);
      expect(launchableUrlOrNull('data:text/plain,hello'), isNull);
      expect(launchableUrlOrNull(null), isNull);
      expect(launchableUrlOrNull('   '), isNull);
    });

    test('the preview card and the Links list keep the narrower rule', () {
      // Only the tap handler in the message body grew: a link preview or a
      // "Links" row for `mailto:` would be nonsense.
      expect(webUrlOrNull('mailto:chiara@example.com'), isNull);
      expect(webUrlOrNull('tel:+34655000011'), isNull);
    });
  });
}
