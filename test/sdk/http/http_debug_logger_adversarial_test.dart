import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

HttpDebugLogger _logger() => HttpDebugLogger((_, __) {});

void main() {
  group('HttpDebugLogger adversarial — deep nesting', () {
    test('redacts password buried four levels deep', () {
      final rendered = _logger().renderBody({
        'user': {
          'profile': {
            'credentials': {'password': 'secret'},
          },
        },
      });

      expect(rendered, isNot(contains('secret')));
      expect(rendered, contains('<redacted>'));
    });

    test('redacts every password inside a list of maps', () {
      final rendered = _logger().renderBody({
        'items': [
          {'password': 'a'},
          {'password': 'b'},
          {'password': 'c'},
        ],
      });

      expect(rendered, isNot(contains('"a"')));
      expect(rendered, isNot(contains('"b"')));
      expect(rendered, isNot(contains('"c"')));
      expect(rendered, isNot(contains(': a')));
      expect(rendered, isNot(contains(': b')));
      expect(rendered, isNot(contains(': c')));
      final redactionCount = '<redacted>'.allMatches(rendered).length;
      expect(redactionCount, 3);
    });

    test('redacts password inside a top-level list with mixed entries', () {
      final rendered = _logger().renderBody([
        {'password': 'x'},
        'literal-string',
        42,
      ]);

      expect(rendered, isNot(contains(': x')));
      expect(rendered, isNot(contains('"x"')));
      expect(rendered, contains('literal-string'));
      expect(rendered, contains('42'));
      expect(rendered, contains('<redacted>'));
    });

    test('redacts the entire object when the key is sensitive', () {
      final rendered = _logger().renderBody({
        'token': {'value': 'jwt-payload', 'expires': '2026-12-31'},
      });

      expect(rendered, isNot(contains('jwt-payload')));
      expect(rendered, isNot(contains('2026-12-31')));
      expect(rendered, contains('<redacted>'));
    });
  });

  group('HttpDebugLogger adversarial — case insensitivity', () {
    test(
      'redacts mixed-case variants whose lowercased form contains a needle',
      () {
        final rendered = _logger().renderBody({
          'Password': 'aa',
          'PASSWORD': 'bb',
          'passWORD': 'dd',
        });

        for (final v in ['aa', 'bb', 'dd']) {
          expect(
            rendered,
            isNot(contains(v)),
            reason: 'leak detected for case variant value: $v',
          );
        }
        final redactionCount = '<redacted>'.allMatches(rendered).length;
        expect(redactionCount, 3);
      },
    );

    test(
      'separator-broken keys ("PASS_WORD") are redacted via normalised match',
      () {
        final rendered = _logger().renderBody({'PASS_WORD': 'cc'});

        expect(
          rendered,
          isNot(contains('cc')),
          reason:
              'PASS_WORD normalises to "password" which is an exact match in '
              '_sensitiveKeys; the gap documented in earlier versions is closed.',
        );
      },
    );
  });

  group('HttpDebugLogger adversarial — substring matching', () {
    test('redacts password-suffixed keys via substring match', () {
      final rendered = _logger().renderBody({
        'oldPassword': 'old1',
        'newPassword': 'new1',
        'currentPassword': 'cur1',
        'passwordConfirmation': 'conf1',
      });

      for (final v in ['old1', 'new1', 'cur1', 'conf1']) {
        expect(
          rendered,
          isNot(contains(v)),
          reason: 'leak detected: $v should be redacted by substring match',
        );
      }
    });

    test(
      'keys that only resemble safe words pass through (no false positive)',
      () {
        final rendered = _logger().renderBody({
          'keyword': 'public-keyword',
          'mypass-word': 'visible-with-hyphen',
        });

        expect(
          rendered,
          contains('public-keyword'),
          reason:
              '"keyword" must not be confused with "key"; '
              'the redactor only knows password/token/secret/etc.',
        );
        expect(
          rendered,
          contains('visible-with-hyphen'),
          reason:
              '"mypass-word" does not contain the substring "password"; '
              'the hyphen breaks the match by design',
        );
        expect(rendered, isNot(contains('<redacted>')));
      },
    );
  });

  group('HttpDebugLogger adversarial — form-encoded mixed payloads', () {
    test('redacts password and csrf_token, preserves username', () {
      final rendered = _logger().renderBody(
        'username=admin&password=secret&csrf_token=xyz',
      );

      expect(rendered, contains('username=admin'));
      expect(rendered, isNot(contains('=secret')));
      expect(rendered, isNot(contains('=xyz')));
      expect(rendered, contains('password=<redacted>'));
      expect(rendered, contains('token=<redacted>'));
    });

    test('redacts repeated sensitive form fields', () {
      final rendered = _logger().renderBody(
        'token=t1&token=t2&pin=1234&otp=5678',
      );

      expect(rendered, isNot(contains('=t1')));
      expect(rendered, isNot(contains('=t2')));
      expect(rendered, isNot(contains('=1234')));
      expect(rendered, isNot(contains('=5678')));
      expect('<redacted>'.allMatches(rendered).length, 4);
    });
  });

  group('HttpDebugLogger adversarial — JSON-inside-string', () {
    test(
      'a JSON-encoded string nested inside a map IS re-parsed and redacted',
      () {
        final rendered = _logger().renderBody({
          'body': jsonEncode({'password': 'x'}),
        });

        expect(rendered, isNot(contains('"x"')));
        expect(rendered, contains('<redacted>'));
      },
    );

    test('a JSON-encoded list inside a map is parsed and walked', () {
      final rendered = _logger().renderBody({
        'payload': jsonEncode([
          {'access_token': 'tkn-1'},
          {'name': 'plain'},
        ]),
      });

      expect(rendered, isNot(contains('tkn-1')));
      expect(rendered, contains('plain'));
    });

    test('malformed JSON falls back to form-encoded scan without crashing', () {
      const body = '{this is not json password=hunter2}';
      final rendered = _logger().renderBody(body);

      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('password=<redacted>'));
    });
  });

  group('HttpDebugLogger adversarial — binary bodies', () {
    test('Uint8List from list is summarized, not rendered', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(_logger().renderBody(bytes), '<binary 5 bytes>');
    });

    test('plain List<int> is summarized too', () {
      final rendered = _logger().renderBody([1, 2, 3, 4]);
      expect(rendered, '<binary 4 bytes>');
    });

    test('FormData with sensitive field name AND file is fully summarized', () {
      final form = FormData.fromMap({
        'password': 'super-secret-pwd',
        'file': MultipartFile.fromBytes(
          List.filled(64, 0xAA),
          filename: 'avatar.png',
        ),
      });

      final rendered = _logger().renderBody(form);

      expect(
        rendered,
        isNot(contains('super-secret-pwd')),
        reason: 'FormData summary must never leak its text fields',
      );
      expect(rendered, isNot(contains('avatar.png')));
      expect(rendered, startsWith('<binary'));
    });
  });

  group('HttpDebugLogger adversarial — payload size', () {
    test('10KB body is truncated to 512 chars and never leaks the secret', () {
      final padding = 'x' * 10000;
      final body = {'note': padding, 'password': 'hunter2'};

      final rendered = _logger().renderBody(body);

      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('…[+'));
      final visiblePrefix = rendered.split('…[+').first;
      expect(visiblePrefix.length, 512);
    });

    test(
      'known gap: when secret key sorts after a huge value, the redaction '
      'marker can be cut by the 512-char truncation (secret itself stays out)',
      () {
        final padding = 'x' * 10000;
        final body = {'note': padding, 'password': 'hunter2'};

        final rendered = _logger().renderBody(body);

        expect(
          rendered,
          isNot(contains('hunter2')),
          reason:
              'the secret value must never appear, even when the '
              '"<redacted>" marker is itself truncated away',
        );
      },
    );

    test(
      'truncation keeps redaction marker visible when secret sorts first',
      () {
        final padding = 'x' * 600;
        final body = {'password': 'hunter2', 'padding': padding};

        final rendered = _logger().renderBody(body);

        expect(rendered, isNot(contains('hunter2')));
        expect(rendered, contains('<redacted>'));
      },
    );
  });

  group('HttpDebugLogger adversarial — unicode and weirdness', () {
    test('non-ASCII keys pass through without crashing', () {
      final rendered = _logger().renderBody({
        'пароль': 'cyrillic-not-in-needle-list',
        'usuario': 'angela',
        'emoji': 'hello world',
      });

      expect(rendered, contains('cyrillic-not-in-needle-list'));
      expect(rendered, contains('angela'));
      expect(rendered, contains('hello world'));
    });

    test('emoji values do not break rendering or truncation', () {
      final rendered = _logger().renderBody({
        'message': 'send help',
        'password': 'hunter2',
      });

      expect(rendered, contains('send help'));
      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('<redacted>'));
    });

    test('null body is rendered as marker, not crash', () {
      expect(_logger().renderBody(null), '∅');
    });

    test('empty string body renders as empty string', () {
      expect(_logger().renderBody(''), '');
    });

    test('empty map renders without redaction marker', () {
      final rendered = _logger().renderBody(<String, dynamic>{});
      expect(rendered, isNot(contains('<redacted>')));
    });

    test('numeric body is rendered untouched', () {
      expect(_logger().renderBody(42), '42');
    });

    test('boolean body is rendered untouched', () {
      expect(_logger().renderBody(true), 'true');
    });
  });

  group('HttpDebugLogger adversarial — header redaction', () {
    test('redactHeaders covers Set-Cookie response headers', () {
      final out = HttpDebugLogger.redactHeaders({
        'Set-Cookie': 'session=abc123; HttpOnly',
        'Content-Type': 'application/json',
      });

      expect(out['Set-Cookie'], '<redacted>');
      expect(out['Content-Type'], 'application/json');
    });

    test('redactHeaders preserves keys it does not know about', () {
      final out = HttpDebugLogger.redactHeaders({
        'X-Trace-Id': 'trace-1',
        'User-Agent': 'noma_chat/1.0',
      });

      expect(out['X-Trace-Id'], 'trace-1');
      expect(out['User-Agent'], 'noma_chat/1.0');
    });
  });
}
