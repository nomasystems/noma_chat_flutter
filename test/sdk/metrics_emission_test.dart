import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockDio extends Mock implements Dio {}

class _NoopAuth extends AuthInterceptor {
  @override
  Future<String> getAuthHeader() async => 'Bearer test';
}

class _CaptureMetrics {
  final List<(String, Map<String, dynamic>)> events = [];
  void call(String name, Map<String, dynamic> data) => events.add((name, data));

  List<(String, Map<String, dynamic>)> named(String name) =>
      events.where((e) => e.$1 == name).toList();
}

class _FakeWebSocketChannel implements WebSocketChannel {
  final _streamController = StreamController<dynamic>.broadcast();
  // ignore: close_sinks
  final _sinkController = StreamController<dynamic>();
  @override
  // ignore: close_sinks
  late final _FakeWebSocketSink sink = _FakeWebSocketSink(_sinkController);

  int? _closeCode;
  String? _closeReason;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void receiveMessage(String message) => _streamController.add(message);

  Future<void> simulateDrop({int? closeCode, String? reason}) async {
    _closeCode = closeCode;
    _closeReason = reason;
    await _streamController.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final List<dynamic> messages = [];

  _FakeWebSocketSink(this._controller);

  @override
  void add(dynamic data) {
    messages.add(data);
    _controller.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  group('MetricCallback — HTTP', () {
    late _MockDio dio;
    late _CaptureMetrics metrics;
    late RestClient rest;

    setUp(() {
      dio = _MockDio();
      metrics = _CaptureMetrics();
      when(() => dio.options).thenReturn(BaseOptions());
      when(() => dio.interceptors).thenReturn(Interceptors());

      rest = RestClient(
        config: ChatConfig.withAuthInterceptor(
          baseUrl: 'http://h/v1',
          realtimeUrl: 'http://h',
          authInterceptor: _NoopAuth(),
          metricCallback: metrics.call,
        ),
        dio: dio,
      );
    });

    test('emits http_request_duration_ms via the _ObservabilityInterceptor on '
        'success — context shape verified', () async {
      when(
        () => dio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
          onSendProgress: any(named: 'onSendProgress'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer((invocation) async {
        final opts = invocation.namedArguments[#options] as Options;
        final ro = RequestOptions(
          path: invocation.positionalArguments[0] as String,
          method: opts.method ?? 'GET',
          extra: {...?opts.extra},
        );
        ro.extra['_noma_started_at_ms'] =
            DateTime.now().millisecondsSinceEpoch - 5;
        // Drive the observability interceptor by hand so we don't
        // depend on the full Dio request lifecycle inside a mock.
        final obs = dio.interceptors.whereType<Interceptor>().firstWhere(
          (i) => i.runtimeType.toString().contains('Observability'),
        );
        final completer = Completer<Response<dynamic>>();
        obs.onResponse(
          Response<dynamic>(
            requestOptions: ro,
            statusCode: 200,
            data: const <String, dynamic>{},
          ),
          _ResponseHandler((r) => completer.complete(r)),
        );
        return completer.future;
      });

      await rest.get('/foo');

      final durations = metrics.named('http_request_duration_ms');
      expect(durations, isNotEmpty);
      final ctx = durations.first.$2;
      expect(ctx.containsKey('path'), isTrue);
      expect(ctx.containsKey('method'), isTrue);
      expect(ctx.containsKey('status'), isTrue);
      expect(ctx.containsKey('duration_ms'), isTrue);
      expect(ctx['requestId'], isA<String>());
    });

    test('emits http_error on error path', () async {
      when(
        () => dio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
          onSendProgress: any(named: 'onSendProgress'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer((invocation) async {
        final opts = invocation.namedArguments[#options] as Options;
        final ro = RequestOptions(
          path: invocation.positionalArguments[0] as String,
          method: opts.method ?? 'GET',
          extra: {...?opts.extra},
        );
        ro.extra['_noma_started_at_ms'] =
            DateTime.now().millisecondsSinceEpoch - 5;
        final obs = dio.interceptors.whereType<Interceptor>().firstWhere(
          (i) => i.runtimeType.toString().contains('Observability'),
        );
        obs.onError(
          DioException(
            requestOptions: ro,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: ro,
              statusCode: 500,
              data: 'boom',
            ),
          ),
          _ErrorHandler((_) {}),
        );
        throw DioException(
          requestOptions: ro,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: ro,
            statusCode: 500,
            data: 'boom',
          ),
        );
      });

      await expectLater(rest.get('/foo'), throwsA(isA<ChatApiException>()));

      final errors = metrics.named('http_error');
      expect(errors, isNotEmpty);
      expect(errors.first.$2['status'], 500);
      expect(errors.first.$2['type'], isNotNull);
    });
  });

  group('MetricCallback — WS', () {
    test('emits ws_disconnect with closeCode + reason + attempts', () async {
      final metrics = _CaptureMetrics();
      late _FakeWebSocketChannel channel;

      final config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 'tok',
        metricCallback: metrics.call,
        maxReconnectAttempts: 0,
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (_) {
          channel = _FakeWebSocketChannel();
          Future.microtask(
            () => channel.receiveMessage(jsonEncode({'type': 'auth_ok'})),
          );
          return channel;
        },
      );

      await transport.connect();
      await channel.simulateDrop(closeCode: 1006, reason: 'abnormal');
      await Future<void>.delayed(Duration.zero);

      final disconnects = metrics.named('ws_disconnect');
      expect(disconnects, isNotEmpty);
      expect(disconnects.first.$2['closeCode'], 1006);
      expect(disconnects.first.$2['reason'], 'abnormal');
      expect(disconnects.first.$2['attempts'], isA<int>());

      await transport.dispose();
    });
  });

  group('MetricCallback — OfflineQueue', () {
    test('emits offline_queue_depth on every persist', () async {
      final metrics = _CaptureMetrics();
      final ds = MemoryChatLocalDatasource();
      final queue = OfflineQueue(store: ds, metricCallback: metrics.call);

      queue.enqueue(PendingSendMessage(id: 'op1', roomId: 'r1', text: 'hi'));
      queue.enqueue(PendingSendMessage(id: 'op2', roomId: 'r1', text: 'ho'));

      // Allow _persistSilent's microtasks to flush.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final depths = metrics.named('offline_queue_depth');
      expect(depths, isNotEmpty);
      expect(depths.last.$2['depth'], 2);
    });
  });
}

class _ResponseHandler extends ResponseInterceptorHandler {
  _ResponseHandler(this._onNext);
  final void Function(Response<dynamic>) _onNext;
  @override
  void next(Response<dynamic> response) => _onNext(response);
}

class _ErrorHandler extends ErrorInterceptorHandler {
  _ErrorHandler(this._onNext);
  final void Function(DioException) _onNext;
  @override
  void next(DioException err) => _onNext(err);
}
