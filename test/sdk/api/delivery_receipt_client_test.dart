import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';

/// Fake [HttpClientAdapter] that captures every request Dio actually sends
/// (after running the full interceptor chain — auth header injection
/// included) and answers with a canned status code, so tests exercise the
/// real request pipeline instead of stubbing `Dio.request` directly (which
/// would skip interceptors entirely).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._statusCode, {this.throwOn});

  final int _statusCode;
  final DioException Function(RequestOptions options)? throwOn;
  final List<RequestOptions> requests = [];
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(await _readBody(requestStream));
    final thrown = throwOn?.call(options);
    if (thrown != null) throw thrown;
    return ResponseBody.fromString('', _statusCode);
  }

  @override
  void close({bool force = false}) {}

  static Future<String> _readBody(Stream<Uint8List>? stream) async {
    if (stream == null) return '';
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  late ChatConfig config;

  setUp(() {
    config = ChatConfig(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 'unused',
      retryConfig: const RetryConfig.disabled(),
    );
  });

  test(
    'PUTs the receipts endpoint with status=delivered and Bearer idToken',
    () async {
      final adapter = _FakeAdapter(204);

      final result = await DeliveryReceiptClient.confirmMessageDelivered(
        config: config,
        idToken: 'fresh-id-token',
        roomId: 'r1',
        messageId: 'msg-7',
        debugDio: _dioWith(adapter),
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.method, 'PUT');
      expect(sent.path, '/rooms/r1/messages/msg-7/receipts');
      expect(sent.headers['Authorization'], 'Bearer fresh-id-token');
      expect(jsonDecode(adapter.bodies.single), {'status': 'delivered'});
    },
  );

  test('does not go through any WS/transport path — pure one-shot REST '
      'call', () async {
    final adapter = _FakeAdapter(204);

    final result = await DeliveryReceiptClient.confirmMessageDelivered(
      config: config,
      idToken: 'tok',
      roomId: 'r2',
      messageId: 'msg-9',
      debugDio: _dioWith(adapter),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('maps a network failure to ChatFailureResult', () async {
    final adapter = _FakeAdapter(
      0,
      throwOn: (options) => DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );

    final result = await DeliveryReceiptClient.confirmMessageDelivered(
      config: config,
      idToken: 'tok',
      roomId: 'r1',
      messageId: 'msg-1',
      debugDio: _dioWith(adapter),
    );

    expect(result.isFailure, isTrue);
    final failure = (result as ChatFailureResult).failure;
    expect(failure, isA<ChatFailure>());
  });

  test(
    'propagates a 401 without retrying (no refresh loop in the lightweight '
    'client)',
    () async {
      final adapter = _FakeAdapter(
        0,
        throwOn: (options) => DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: options, statusCode: 401),
        ),
      );

      final result = await DeliveryReceiptClient.confirmMessageDelivered(
        config: config,
        idToken: 'expired-token',
        roomId: 'r1',
        messageId: 'msg-1',
        debugDio: _dioWith(adapter),
      );

      expect(result.isFailure, isTrue);
      expect(adapter.requests, hasLength(1));
    },
  );
}
