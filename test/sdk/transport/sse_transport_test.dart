import 'package:dio/dio.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/sse_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDio implements Dio {
  final List<String> requestedUrls = [];
  int callCount = 0;
  bool shouldFail = true;

  _FakeDio();

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    callCount++;
    requestedUrls.add(path);
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.cancel,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('SseTransport', () {
    test('uses ssePath and effectiveSseUrl from config', () async {
      final fakeDio = _FakeDio();

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        sseUrl: 'http://localhost:2081',
        ssePath: '/eventsource',
        tokenProvider: () async => 'test-token',
        maxReconnectAttempts: 1,
      );

      final transport = SseTransport(config: config, dio: fakeDio);
      await transport.connect();

      // Wait for the first connection attempt to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(fakeDio.requestedUrls, isNotEmpty);
      expect(fakeDio.requestedUrls.first, 'http://localhost:2081/eventsource');

      await transport.dispose();
    });

    test('defaults to realtimeUrl when sseUrl is not provided', () async {
      final fakeDio = _FakeDio();

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        maxReconnectAttempts: 1,
      );

      final transport = SseTransport(config: config, dio: fakeDio);
      await transport.connect();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(fakeDio.requestedUrls.first, 'http://localhost:8077/events');

      await transport.dispose();
    });

    test('uses custom ssePath', () async {
      final fakeDio = _FakeDio();

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        ssePath: '/custom-events',
        tokenProvider: () async => 'test-token',
        maxReconnectAttempts: 1,
      );

      final transport = SseTransport(config: config, dio: fakeDio);
      await transport.connect();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(fakeDio.requestedUrls.first, 'http://localhost:8077/custom-events');

      await transport.dispose();
    });

    test('stops reconnecting after maxReconnectAttempts', () async {
      final fakeDio = _FakeDio();
      final events = <ChatEvent>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        maxReconnectAttempts: 2,
        wsReconnectDelay: const Duration(milliseconds: 10),
      );

      final transport = SseTransport(config: config, dio: fakeDio);
      transport.events.listen(events.add);
      transport.stateChanges.listen((_) {});

      await transport.connect();

      // Wait for reconnect attempts to exhaust (backoff + up to 1s jitter per attempt)
      await Future.delayed(const Duration(milliseconds: 3000));

      // Should have stopped with error state after max attempts
      expect(transport.state, ChatConnectionState.error);
      expect(
        events.whereType<ErrorEvent>().any(
            (e) => e.exception.message.contains('Max reconnect attempts')),
        isTrue,
      );

      await transport.dispose();
    });
  });
}
