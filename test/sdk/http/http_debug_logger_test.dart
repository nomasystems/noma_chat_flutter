import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _CapturingLogger {
  final List<(String, String)> entries = [];

  void call(String level, String message) {
    entries.add((level, message));
  }
}

void main() {
  group('HttpDebugLogger redaction — JSON body', () {
    test('redacts top-level password in a Map body', () {
      final logger = _CapturingLogger();
      final interceptor = HttpDebugLogger(logger.call);

      final rendered = interceptor.renderBody({
        'email': 'a@b.com',
        'password': 'hunter2',
      });

      expect(rendered, contains('email: a@b.com'));
      expect(rendered, contains('password: <redacted>'));
      expect(rendered, isNot(contains('hunter2')));
    });

    test('redacts nested token inside a Map body', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({
        'session': {
          'token': 'eyJhbGciOi.payload.sig',
          'expires_at': '2026-12-31',
        },
        'user': {'id': 'u-1'},
      });

      expect(rendered, contains('token: <redacted>'));
      expect(rendered, contains('expires_at: 2026-12-31'));
      expect(rendered, contains('id: u-1'));
      expect(rendered, isNot(contains('eyJhbGciOi.payload.sig')));
    });

    test('redacts inside lists of maps', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({
        'items': [
          {'name': 'a', 'api_key': 'k1'},
          {'name': 'b', 'access_token': 't2'},
        ],
      });

      expect(rendered, isNot(contains('k1')));
      expect(rendered, isNot(contains('t2')));
      expect(rendered, contains('api_key: <redacted>'));
      expect(rendered, contains('access_token: <redacted>'));
    });

    test('matches sensitive keys case-insensitively', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({
        'Password': 'p1',
        'AUTHORIZATION': 'Bearer x',
        'My-Secret-Value': 'oops',
      });

      expect(rendered, isNot(contains('p1')));
      expect(rendered, isNot(contains('Bearer x')));
      expect(rendered, isNot(contains('oops')));
      expect(rendered.split('<redacted>').length - 1, 3);
    });

    test('does not touch keys that only resemble safe words', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({
        'username': 'alice',
        'email': 'alice@b.com',
        'display_name': 'Alice',
      });

      expect(rendered, contains('alice'));
      expect(rendered, contains('alice@b.com'));
      expect(rendered, contains('Alice'));
      expect(rendered, isNot(contains('<redacted>')));
    });
  });

  group('HttpDebugLogger redaction — JSON string body', () {
    test('redacts password in a JSON-encoded String body', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final body = jsonEncode({'email': 'a@b.com', 'password': 'hunter2'});

      final rendered = interceptor.renderBody(body);

      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('<redacted>'));
      expect(rendered, contains('a@b.com'));
    });

    test('redacts nested token in a JSON-encoded String body', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final body = jsonEncode({
        'session': {'token': 'jwt-here'},
      });

      final rendered = interceptor.renderBody(body);

      expect(rendered, isNot(contains('jwt-here')));
      expect(rendered, contains('<redacted>'));
    });
  });

  group('HttpDebugLogger redaction — form-encoded', () {
    test('redacts password in a form-encoded body', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody(
        'email=a%40b.com&password=hunter2&remember=true',
      );

      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('password=<redacted>'));
      expect(rendered, contains('email=a%40b.com'));
      expect(rendered, contains('remember=true'));
    });

    test('redacts multiple sensitive form fields at once', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody(
        'access_token=abc&refresh_token=def&user=alice',
      );

      expect(rendered, isNot(contains('abc')));
      expect(rendered, isNot(contains('def')));
      expect(rendered, contains('access_token=<redacted>'));
      expect(rendered, contains('refresh_token=<redacted>'));
      expect(rendered, contains('user=alice'));
    });
  });

  group('HttpDebugLogger redaction — binary', () {
    test('FormData with bytes is summarized as <binary N bytes>', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final bytes = Uint8List.fromList(List.filled(2048, 0xAB));
      final form = FormData.fromMap({
        'caption': 'a photo',
        'file': MultipartFile.fromBytes(bytes, filename: 'x.bin'),
      });

      final rendered = interceptor.renderBody(form);

      expect(rendered, '<binary 2048 bytes>');
      expect(rendered, isNot(contains('a photo')));
    });

    test('Uint8List body is summarized as <binary N bytes>', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final bytes = Uint8List.fromList(List.filled(128, 1));

      final rendered = interceptor.renderBody(bytes);

      expect(rendered, '<binary 128 bytes>');
    });

    test('Stream body is summarized as <binary stream>', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final stream = Stream<List<int>>.fromIterable([
        [1, 2, 3],
      ]);

      final rendered = interceptor.renderBody(stream);

      expect(rendered, '<binary stream>');
    });
  });

  group('HttpDebugLogger redaction — passthrough', () {
    test('null body is rendered as the empty marker', () {
      final interceptor = HttpDebugLogger((_, __) {});
      expect(interceptor.renderBody(null), '∅');
    });

    test('plain Map without secrets is rendered untouched', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({
        'title': 'hello',
        'body': 'world',
        'count': 7,
      });

      expect(rendered, contains('title: hello'));
      expect(rendered, contains('body: world'));
      expect(rendered, contains('count: 7'));
      expect(rendered, isNot(contains('<redacted>')));
    });

    test('plain String body without secrets is unchanged', () {
      final interceptor = HttpDebugLogger((_, __) {});
      const body = 'a small note';

      expect(interceptor.renderBody(body), body);
    });
  });

  group('HttpDebugLogger truncation', () {
    test('truncates to 512 chars AFTER redacting the body', () {
      final interceptor = HttpDebugLogger((_, __) {});
      final padding = 'x' * 600;
      final body = {'name': padding, 'password': 'hunter2'};

      final rendered = interceptor.renderBody(body);

      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, contains('…[+'));
      final visiblePrefix = rendered.split('…[+').first;
      expect(visiblePrefix.length, 512);
    });

    test('short body is not truncated and keeps the redacted marker', () {
      final interceptor = HttpDebugLogger((_, __) {});

      final rendered = interceptor.renderBody({'token': 'jwt'});

      expect(rendered, isNot(contains('…[+')));
      expect(rendered, contains('<redacted>'));
    });
  });

  group('HttpDebugLogger.redactHeaders', () {
    test('redacts Authorization, Cookie, and x-api-key (case-insensitive)', () {
      final out = HttpDebugLogger.redactHeaders({
        'Authorization': 'Bearer jwt',
        'cookie': 'sid=xyz',
        'X-API-Key': 'k',
        'Content-Type': 'application/json',
      });

      expect(out['Authorization'], '<redacted>');
      expect(out['cookie'], '<redacted>');
      expect(out['X-API-Key'], '<redacted>');
      expect(out['Content-Type'], 'application/json');
    });
  });

  group('HttpDebugLogger interceptor wiring', () {
    test('onRequest emits a debug line with redacted body', () {
      final logger = _CapturingLogger();
      final interceptor = HttpDebugLogger(logger.call);
      final opts = RequestOptions(
        path: '/v1/users/auth/login',
        method: 'POST',
        data: {'email': 'a@b.com', 'password': 'hunter2'},
        baseUrl: 'http://h',
      );

      var passedThrough = false;
      interceptor.onRequest(
        opts,
        _StubRequestHandler(() {
          passedThrough = true;
        }),
      );

      expect(passedThrough, isTrue);
      expect(logger.entries, hasLength(1));
      expect(logger.entries.first.$1, 'debug');
      expect(logger.entries.first.$2, contains('http.req POST'));
      expect(logger.entries.first.$2, contains('<redacted>'));
      expect(logger.entries.first.$2, isNot(contains('hunter2')));
    });
  });
}

class _StubRequestHandler extends RequestInterceptorHandler {
  _StubRequestHandler(this._onNext);

  final void Function() _onNext;

  @override
  void next(RequestOptions requestOptions) {
    _onNext();
  }
}
