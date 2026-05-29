import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

void main() {
  group('sanitizeUuidsInLogLine', () {
    test('replaces a single UUID with a 5-char prefix + ellipsis', () {
      final out = sanitizeUuidsInLogLine(
        '/v1/rooms/abc12345-6789-abcd-ef01-234567890abc/messages',
      );
      expect(out, '/v1/rooms/<UUID:abc12...>/messages');
    });

    test('replaces multiple UUIDs in a single string', () {
      final out = sanitizeUuidsInLogLine(
        '/v1/rooms/aaaaaaaa-1111-2222-3333-444444444444/'
        'messages/bbbbbbbb-5555-6666-7777-888888888888',
      );
      expect(
        out,
        '/v1/rooms/<UUID:aaaaa...>/'
        'messages/<UUID:bbbbb...>',
      );
    });

    test('is case-insensitive (uppercase UUIDs are also redacted)', () {
      final out = sanitizeUuidsInLogLine(
        'GET /v1/users/ABCD1234-5678-9ABC-DEF0-1234567890AB',
      );
      expect(out, 'GET /v1/users/<UUID:ABCD1...>');
    });

    test('leaves strings without UUIDs untouched', () {
      expect(sanitizeUuidsInLogLine('/v1/rooms/list'), '/v1/rooms/list');
    });

    test('does not match almost-UUIDs (wrong group lengths)', () {
      const malformed = '/v1/rooms/12345678-1234-1234-1234-12345/messages';
      expect(sanitizeUuidsInLogLine(malformed), malformed);
    });
  });

  group('HttpDebugLogger UUID sanitization in log lines', () {
    test('onRequest redacts UUID segments in the rendered URI', () {
      final logs = <String>[];
      final logger = HttpDebugLogger((_, msg) => logs.add(msg));
      final opts = RequestOptions(
        path: '/v1/rooms/abc12345-6789-abcd-ef01-234567890abc/messages',
        method: 'POST',
        baseUrl: 'http://h',
      );
      var passed = false;
      logger.onRequest(opts, _StubRequestHandler(() => passed = true));

      expect(passed, isTrue);
      expect(logs, hasLength(1));
      expect(logs.first, contains('<UUID:abc12...>'));
      expect(
        logs.first,
        isNot(contains('abc12345-6789-abcd-ef01-234567890abc')),
      );
    });
  });
}

class _StubRequestHandler extends RequestInterceptorHandler {
  _StubRequestHandler(this._onNext);
  final void Function() _onNext;
  @override
  void next(RequestOptions requestOptions) => _onNext();
}
