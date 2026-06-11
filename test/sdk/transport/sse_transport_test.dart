import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
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

/// Fake Dio that returns a streaming response backed by a controllable
/// `StreamController<Uint8List>`. Tests push chunks via [pushChunk] and
/// can verify reconnects through [callCount].
class _StreamingFakeDio implements Dio {
  int callCount = 0;
  final List<StreamController<Uint8List>> _controllers = [];
  // After this many successful streaming calls, subsequent get() throws
  // a connectionError so the reconnect loop terminates predictably.
  int maxSuccessfulCalls = 1;

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
    if (callCount > maxSuccessfulCalls) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    final controller = StreamController<Uint8List>();
    _controllers.add(controller);
    cancelToken?.whenCancel.then((_) {
      if (!controller.isClosed) controller.close();
    });
    final body = ResponseBody(controller.stream, 200);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: body as T,
      statusCode: 200,
    );
  }

  void pushChunk(String text) {
    // `_controllers.last` is owned by the surrounding test harness — it
    // lives in `_controllers` and is closed in `closeAll()` below. The
    // `close_sinks` lint can't see that ownership, so we silence it
    // explicitly here.
    // ignore: close_sinks
    final c = _controllers.last;
    if (!c.isClosed) c.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> closeAll() async {
    for (final c in _controllers) {
      if (!c.isClosed) await c.close();
    }
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

      expect(fakeDio.requestedUrls.first, 'http://localhost:8077/eventsource');

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

      expect(
        fakeDio.requestedUrls.first,
        'http://localhost:8077/custom-events',
      );

      await transport.dispose();
    });

    test('idle timeout cancels stream and triggers reconnect', () async {
      final dio = _StreamingFakeDio();
      final events = <ChatEvent>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        sseIdleTimeout: const Duration(milliseconds: 80),
        wsReconnectDelay: const Duration(milliseconds: 10),
        maxReconnectAttempts: 2,
      );

      final transport = SseTransport(config: config, dio: dio);
      transport.events.listen(events.add);
      transport.stateChanges.listen((_) {});

      await transport.connect();
      // Initial connect resolves, no chunks pushed → watchdog fires ~80 ms.
      // Allow generous time for backoff (10 ms base + up to 1 s jitter).
      await Future.delayed(const Duration(milliseconds: 1500));

      expect(
        dio.callCount,
        greaterThanOrEqualTo(2),
        reason: 'watchdog should have forced at least one reconnect',
      );
      expect(
        events.whereType<ErrorEvent>().any(
          (e) => e.exception is ChatSseIdleTimeoutException,
        ),
        isTrue,
        reason: 'a ChatSseIdleTimeoutException should be emitted',
      );

      await transport.dispose();
      await dio.closeAll();
    });

    test('chunks reset the idle timer', () async {
      final dio = _StreamingFakeDio();
      final events = <ChatEvent>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        sseIdleTimeout: const Duration(milliseconds: 100),
        wsReconnectDelay: const Duration(milliseconds: 10),
        maxReconnectAttempts: 2,
      );

      final transport = SseTransport(config: config, dio: dio);
      transport.events.listen(events.add);
      transport.stateChanges.listen((_) {});

      // Fire-and-forget: connect() awaits the streaming `await for` loop,
      // which only completes when we close the stream below.
      unawaited(transport.connect());
      // Push a keep-alive comment every 40 ms for 240 ms (6 ticks).
      // Each chunk resets the 100 ms watchdog → it never fires.
      for (var i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 40));
        dio.pushChunk(': ping\n\n');
      }

      expect(dio.callCount, 1, reason: 'no reconnect should occur');
      expect(
        events.whereType<ErrorEvent>().any(
          (e) => e.exception is ChatSseIdleTimeoutException,
        ),
        isFalse,
      );

      await transport.dispose();
      await dio.closeAll();
    });

    test('sseIdleTimeout: null disables the watchdog', () async {
      final dio = _StreamingFakeDio();

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        sseIdleTimeout: null,
        wsReconnectDelay: const Duration(milliseconds: 10),
        maxReconnectAttempts: 2,
      );

      final transport = SseTransport(config: config, dio: dio);
      transport.events.listen((_) {});
      transport.stateChanges.listen((_) {});

      // Fire-and-forget: connect() awaits the streaming loop that never ends
      // when there are no chunks and the watchdog is off.
      unawaited(transport.connect());
      // No chunks and no watchdog: stays connected.
      await Future.delayed(const Duration(milliseconds: 300));

      expect(dio.callCount, 1);

      await transport.dispose();
      await dio.closeAll();
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
          (e) => e.exception.message.contains('Max reconnect attempts'),
        ),
        isTrue,
      );

      await transport.dispose();
    });
  });
}
