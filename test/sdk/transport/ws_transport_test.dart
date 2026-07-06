import 'dart:async';
import 'dart:convert';

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({bool autoAuthOk = false}) {
    if (autoAuthOk) {
      _streamController.onListen = () {
        scheduleMicrotask(() {
          if (!_streamController.isClosed) {
            _streamController.add(jsonEncode({'type': 'auth_ok'}));
          }
        });
      };
    }
  }

  final _streamController = StreamController<dynamic>.broadcast();
  final _sinkController = StreamController<dynamic>(); // ignore: close_sinks
  @override
  // ignore: close_sinks
  late final _FakeWebSocketSink sink = _FakeWebSocketSink(_sinkController);

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void receiveMessage(String message) => _streamController.add(message);

  Future<void> simulateDrop() async {
    await _streamController.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final List<dynamic> messages = [];
  int closeCalls = 0;

  _FakeWebSocketSink(this._controller);

  @override
  void add(dynamic data) {
    messages.add(data);
    _controller.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('WsTransport', () {
    test('connects using realtimeUrl, not baseUrl', () async {
      Uri? capturedUri;
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'https://api.example.com',
        realtimeUrl: 'https://realtime.example.com:8080',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          capturedUri = uri;
          fakeChannel = _FakeWebSocketChannel();
          // Simulate auth success after a short delay
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.host, equals('realtime.example.com'));
      expect(capturedUri!.port, equals(8080));
      expect(capturedUri!.path, equals('/ws'));
      expect(capturedUri!.scheme, equals('wss'));
      // Must NOT use baseUrl host
      expect(capturedUri!.host, isNot(equals('api.example.com')));

      await transport.dispose();
    });

    test('off-contract frame does not break event delivery', () async {
      late _FakeWebSocketChannel fakeChannel;
      final config = ChatConfig(
        baseUrl: 'https://api.example.com',
        realtimeUrl: 'https://realtime.example.com',
        tokenProvider: () async => 'test-token',
      );
      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      final received = <ChatEvent>[];
      final sub = transport.events.listen(received.add);
      await transport.connect();
      await Future<void>.delayed(Duration.zero);

      // A backend field shipped off-contract (roomId as a number where a
      // String is expected) must be dropped, not thrown out of the stream.
      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'new_message',
          'roomId': 42,
          'message': {'messageId': 'm0', 'from': 'u0', 'text': 'x'},
        }),
      );
      // The stream must still be alive: a subsequent valid frame is delivered.
      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'new_message',
          'roomId': 'room-1',
          'message': {
            'messageId': 'm1',
            'from': 'user-1',
            'text': 'hello',
            'timestamp': '2024-01-01T00:00:00.000Z',
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);

      final messages = received.whereType<NewMessageEvent>().toList();
      expect(messages, hasLength(1));
      expect(messages.single.roomId, equals('room-1'));

      await sub.cancel();
      await transport.dispose();
    });

    test('converts https realtimeUrl to wss scheme', () async {
      Uri? capturedUri;

      final config = ChatConfig(
        baseUrl: 'https://api.example.com',
        realtimeUrl: 'https://ws.example.com/chat',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          capturedUri = uri;
          final channel = _FakeWebSocketChannel();
          Future.microtask(() {
            channel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return channel;
        },
      );

      await transport.connect();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.scheme, equals('wss'));
      expect(capturedUri!.host, equals('ws.example.com'));
      expect(capturedUri!.path, equals('/chat/ws'));

      await transport.dispose();
    });

    test('converts http realtimeUrl to ws scheme (with port)', () async {
      Uri? capturedUri;

      final config = ChatConfig(
        baseUrl: 'http://localhost:3000',
        realtimeUrl: 'http://localhost:5280',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          capturedUri = uri;
          final channel = _FakeWebSocketChannel();
          Future.microtask(() {
            channel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return channel;
        },
      );

      await transport.connect();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.scheme, equals('ws'));
      expect(capturedUri!.host, equals('localhost'));
      expect(capturedUri!.port, equals(5280));
      expect(capturedUri!.path, equals('/ws'));

      await transport.dispose();
    });

    test('converts http realtimeUrl to ws scheme', () async {
      Uri? capturedUri;

      final config = ChatConfig(
        baseUrl: 'https://api.example.com',
        realtimeUrl: 'http://realtime.local:8080/path',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          capturedUri = uri;
          final channel = _FakeWebSocketChannel();
          Future.microtask(() {
            channel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return channel;
        },
      );

      await transport.connect();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.scheme, equals('ws'));
      expect(capturedUri!.host, equals('realtime.local'));
      expect(capturedUri!.port, equals(8080));
      expect(capturedUri!.path, equals('/path/ws'));

      await transport.dispose();
    });

    test('uses custom wsPath from config', () async {
      Uri? capturedUri;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        wsPath: '/custom-ws',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          capturedUri = uri;
          final channel = _FakeWebSocketChannel();
          Future.microtask(() {
            channel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return channel;
        },
      );

      await transport.connect();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.path, equals('/custom-ws'));

      await transport.dispose();
    });

    test('unwraps event envelope with type=event and data payload', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is NewMessageEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'event',
          'data': {
            'type': 'new_message',
            'roomId': 'room-1',
            'message': {
              'id': 'msg-1',
              'from': 'user-1',
              'text': 'Hello',
              'timestamp': '2026-01-01T00:00:00Z',
            },
          },
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      final event = events.first as NewMessageEvent;
      expect(event.roomId, equals('room-1'));
      expect(event.message.id, equals('msg-1'));
      expect(event.message.text, equals('Hello'));

      await sub.cancel();
      await transport.dispose();
    });

    test('handles flat WS events without envelope', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is RoomDeletedEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({'type': 'room_deleted', 'roomId': 'room-2'}),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect((events.first as RoomDeletedEvent).roomId, equals('room-2'));

      await sub.cancel();
      await transport.dispose();
    });

    test('envelope with null data is ignored', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(jsonEncode({'type': 'event', 'data': null}));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);

      await sub.cancel();
      await transport.dispose();
    });

    test('envelope with non-map data is ignored', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({'type': 'event', 'data': 'string_data'}),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);

      await sub.cancel();
      await transport.dispose();
    });

    test('envelope with unknown event type in data is ignored', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'event',
          'data': {'type': 'totally_unknown', 'foo': 'bar'},
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);

      await sub.cancel();
      await transport.dispose();
    });

    test('rapid consecutive events maintain order', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is NewMessageEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'event',
          'data': {
            'type': 'new_message',
            'roomId': 'room-1',
            'message': {
              'id': 'msg-1',
              'from': 'user-1',
              'text': 'First',
              'timestamp': '2026-01-01T00:00:00Z',
            },
          },
        }),
      );

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'new_message',
          'roomId': 'room-1',
          'message': {
            'id': 'msg-2',
            'from': 'user-1',
            'text': 'Second',
            'timestamp': '2026-01-01T00:00:01Z',
          },
        }),
      );

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'event',
          'data': {
            'type': 'new_message',
            'roomId': 'room-1',
            'message': {
              'id': 'msg-3',
              'from': 'user-1',
              'text': 'Third',
              'timestamp': '2026-01-01T00:00:02Z',
            },
          },
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(3));
      expect((events[0] as NewMessageEvent).message.id, equals('msg-1'));
      expect((events[1] as NewMessageEvent).message.id, equals('msg-2'));
      expect((events[2] as NewMessageEvent).message.id, equals('msg-3'));

      await sub.cancel();
      await transport.dispose();
    });

    test('sends raw token without Bearer prefix during auth', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'my-secret-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final authMessage = fakeChannel.sink.messages
          .whereType<String>()
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .firstWhere((m) => m['type'] == 'auth');

      expect(authMessage['token'], equals('my-secret-token'));
      expect(authMessage['token'], isNot(contains('Bearer')));

      await transport.dispose();
    });

    test('event with null optional fields deserializes correctly', () async {
      late _FakeWebSocketChannel fakeChannel;

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(() {
            fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          });
          return fakeChannel;
        },
      );

      await transport.connect();

      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is NewMessageEvent)
          .listen(events.add);

      fakeChannel.receiveMessage(
        jsonEncode({
          'type': 'event',
          'data': {
            'type': 'new_message',
            'roomId': 'room-1',
            'message': {
              'id': 'msg-minimal',
              'from': 'user-1',
              'text': 'Minimal message',
              'timestamp': '2026-01-01T00:00:00Z',
            },
          },
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      final event = events.first as NewMessageEvent;
      expect(event.roomId, equals('room-1'));
      expect(event.message.id, equals('msg-minimal'));
      expect(event.message.from, equals('user-1'));
      expect(event.message.text, equals('Minimal message'));

      await sub.cancel();
      await transport.dispose();
    });

    test('connect() while already connected does not reopen the channel '
        'nor reset the reconnect counter', () async {
      final channels = <_FakeWebSocketChannel>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        wsReconnectDelay: const Duration(milliseconds: 5),
        maxReconnectAttempts: 2,
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          final channel = _FakeWebSocketChannel(autoAuthOk: true);
          channels.add(channel);
          return channel;
        },
      );

      await transport.connect();
      expect(channels, hasLength(1));

      await transport.connect();
      expect(
        channels,
        hasLength(1),
        reason:
            'connect() while already connected must be a no-op; it '
            'must NOT reopen the channel nor reset the reconnect '
            'counter',
      );

      await transport.dispose();
    });

    test(
      'auth_ok resets reconnect counter so capped attempts apply per '
      'authenticated session, not for the lifetime of the transport',
      () async {
        final channels = <_FakeWebSocketChannel>[];

        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          wsReconnectDelay: const Duration(milliseconds: 5),
          maxReconnectAttempts: 2,
        );

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            final channel = _FakeWebSocketChannel(autoAuthOk: true);
            channels.add(channel);
            return channel;
          },
        );

        Future<void> dropAndAwaitReconnect(int expectedTotal) async {
          await channels.last.simulateDrop();
          for (var i = 0; i < 200 && channels.length < expectedTotal; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }

        await transport.connect();
        expect(channels, hasLength(1));

        await dropAndAwaitReconnect(2);
        expect(channels, hasLength(2));

        await dropAndAwaitReconnect(3);
        expect(channels, hasLength(3));

        await dropAndAwaitReconnect(4);
        expect(
          channels,
          hasLength(4),
          reason:
              'each successful auth_ok resets the attempt counter, so a '
              'single drop after an authenticated session always yields '
              'exactly one reconnect',
        );

        await transport.dispose();
      },
    );

    test('close 4003 explicitly closes the client sink before the '
        'reconnect opens a new channel', () async {
      final channels = <_FakeWebSocketChannel>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        wsReconnectDelay: const Duration(milliseconds: 5),
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          final channel = _FakeWebSocketChannel(autoAuthOk: true);
          channels.add(channel);
          return channel;
        },
      );

      await transport.connect();
      final first = channels.first;

      first.closeCode = 4003;
      await first.simulateDrop();

      for (var i = 0; i < 200 && first.sink.closeCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(first.sink.closeCalls, 1);

      for (var i = 0; i < 200 && channels.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(channels, hasLength(2));
      expect(first.sink.closeCalls, 1);

      await transport.dispose();
    });

    test('emits ws_auth_timeout metric and structured warn log when the '
        'auth handshake expires', () async {
      final metrics = <(String, Map<String, dynamic>)>[];
      final logs = <String>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        authTimeout: const Duration(milliseconds: 50),
        maxReconnectAttempts: 0,
        logger: (level, message) => logs.add('$level: $message'),
        metricCallback: (metric, data) => metrics.add((metric, data)),
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) => _FakeWebSocketChannel(),
      );

      await transport.connect();

      final timeoutMetrics = metrics
          .where((m) => m.$1 == 'ws_auth_timeout')
          .toList();
      expect(timeoutMetrics, hasLength(1));
      expect(timeoutMetrics.single.$2['timeoutMs'], 50);
      expect(
        logs.any(
          (l) => l.startsWith('warn:') && l.contains('auth handshake timed out'),
        ),
        isTrue,
      );

      await transport.dispose();
    });

    test('dispose() cancels a pending reconnect and suppresses late '
        'emissions', () async {
      final channels = <_FakeWebSocketChannel>[];
      final states = <ChatConnectionState>[];

      final config = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        wsReconnectDelay: const Duration(milliseconds: 20),
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          final channel = _FakeWebSocketChannel(autoAuthOk: true);
          channels.add(channel);
          return channel;
        },
      );

      await transport.connect();
      final sub = transport.stateChanges.listen(states.add);

      await channels.first.simulateDrop();
      await transport.dispose();
      final statesAtDispose = List<ChatConnectionState>.from(states);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(channels, hasLength(1));
      expect(states, statesAtDispose);

      await sub.cancel();
    });
  });
}
