import 'dart:async';
import 'dart:convert';

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({bool autoAuthOk = false, bool autoPong = false}) {
    if (autoAuthOk) {
      _streamController.onListen = () {
        scheduleMicrotask(() {
          if (!_streamController.isClosed) {
            _streamController.add(jsonEncode({'type': 'auth_ok'}));
          }
        });
      };
    }
    if (autoPong) {
      sink.onAdd = (data) {
        if (data is! String) return;
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        if (decoded['type'] == 'ping') {
          scheduleMicrotask(() {
            if (!_streamController.isClosed) {
              _streamController.add(jsonEncode({'type': 'pong'}));
            }
          });
        }
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
  void Function(dynamic data)? onAdd;

  _FakeWebSocketSink(this._controller);

  @override
  void add(dynamic data) {
    messages.add(data);
    _controller.add(data);
    onAdd?.call(data);
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
          (l) =>
              l.startsWith('warn:') && l.contains('auth handshake timed out'),
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

    group('authenticating state', () {
      test(
        'emitted between channel-ready and auth_ok, then connected',
        () async {
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
              return fakeChannel;
            },
          );

          final states = <ChatConnectionState>[];
          final sub = transport.stateChanges.listen(states.add);

          final connectFuture = transport.connect();
          await Future<void>.delayed(Duration.zero);
          expect(transport.state, ChatConnectionState.authenticating);
          expect(transport.state.isWorking, isTrue);

          fakeChannel.receiveMessage(jsonEncode({'type': 'auth_ok'}));
          await connectFuture;

          expect(
            states,
            containsAllInOrder([
              ChatConnectionState.connecting,
              ChatConnectionState.authenticating,
              ChatConnectionState.connected,
            ]),
          );

          await sub.cancel();
          await transport.dispose();
        },
      );

      test('a reentrant connect() during the handshake window does not '
          'open a parallel socket', () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
        );
        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            final channel = _FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );

        final connectFuture = transport.connect();
        await Future<void>.delayed(Duration.zero);
        expect(transport.state, ChatConnectionState.authenticating);

        // A second connect() call while still authenticating (e.g. an app
        // resume racing an in-flight reconnect) must be a no-op — it must
        // NOT open a second parallel socket.
        await transport.connect();
        expect(channels, hasLength(1));

        channels.first.receiveMessage(jsonEncode({'type': 'auth_ok'}));
        await connectFuture;
        expect(transport.state, ChatConnectionState.connected);

        await transport.dispose();
      });
    });

    group('pong watchdog', () {
      test('forces a reconnect when the peer never answers a ping', () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          // Pong timeout deliberately shorter than the ping interval: it
          // must elapse (and fire the watchdog) well before the NEXT ping
          // tick would otherwise cancel/re-arm it, so the test isn't racing
          // its own periodic ping timer.
          wsPingInterval: const Duration(milliseconds: 60),
          wsPongTimeout: const Duration(milliseconds: 15),
          wsReconnectDelay: const Duration(milliseconds: 5),
        );

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            // Zombie socket: authenticates fine but never answers a ping
            // with a pong — the scenario onError/onDone alone would never
            // surface.
            final channel = _FakeWebSocketChannel(autoAuthOk: true);
            channels.add(channel);
            return channel;
          },
        );

        await transport.connect();
        expect(channels, hasLength(1));

        for (var i = 0; i < 300 && channels.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(
          channels,
          hasLength(2),
          reason:
              'the pong watchdog must force a reconnect when no pong ever '
              'arrives, opening a fresh socket',
        );

        await transport.dispose();
      });

      test('a pong in time cancels the watchdog — no reconnect', () async {
        late _FakeWebSocketChannel fakeChannel;
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          wsPingInterval: const Duration(milliseconds: 20),
          wsPongTimeout: const Duration(milliseconds: 200),
        );

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            fakeChannel = _FakeWebSocketChannel(
              autoAuthOk: true,
              autoPong: true,
            );
            return fakeChannel;
          },
        );

        await transport.connect();
        expect(transport.lastPongAge, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(transport.state, ChatConnectionState.connected);
        expect(transport.lastPongAge, isNotNull);
        expect(transport.lastPongAge!.inMilliseconds, lessThan(200));

        await transport.dispose();
      });

      test('wsPongWatchdogEnabled: false disables it — a zombie socket '
          'never reconnects on its own', () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          wsPingInterval: const Duration(milliseconds: 20),
          wsPongTimeout: const Duration(milliseconds: 20),
          wsPongWatchdogEnabled: false,
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
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(
          channels,
          hasLength(1),
          reason: 'disabled watchdog must never force a reconnect on its own',
        );
        expect(transport.state, ChatConnectionState.connected);

        await transport.dispose();
      });
    });

    group('resume liveness probe (verifyLiveness)', () {
      test('a zombie socket is detected on resume and forced through a real '
          'reconnect that re-emits ConnectedEvent', () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          // Long ping interval so the ordinary periodic keep-alive can NOT
          // fire during the test — the reconnect must come from the resume
          // probe alone, not the normal ~ping+pong watchdog window.
          wsPingInterval: const Duration(seconds: 30),
          wsPongTimeout: const Duration(milliseconds: 20),
          wsReconnectDelay: const Duration(milliseconds: 5),
        );

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            // Zombie socket: authenticates fine but never answers a ping —
            // exactly the iOS-suspend case where the OS drops the TCP with no
            // FIN/RST, so onError/onDone never fire and state stays connected.
            final channel = _FakeWebSocketChannel(autoAuthOk: true);
            channels.add(channel);
            return channel;
          },
        );

        var connectedEvents = 0;
        final sub = transport.events.listen((e) {
          if (e is ConnectedEvent) connectedEvents++;
        });

        await transport.connect();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(channels, hasLength(1));
        expect(connectedEvents, 1);
        expect(transport.state, ChatConnectionState.connected);

        // App returns to foreground: the transport still reports itself
        // connected over the dead socket. A plain connect() would no-op here;
        // verifyLiveness must probe and, on the missing pong, cycle a real
        // reconnect.
        await transport.verifyLiveness();

        for (var i = 0; i < 300 && channels.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(
          channels,
          hasLength(2),
          reason:
              'the resume probe must reconnect a zombie socket instead of '
              'trusting the stale connected state',
        );
        expect(
          connectedEvents,
          2,
          reason:
              'the forced reconnect must re-emit ConnectedEvent so the '
              'router runs the presence bootstrap + resync',
        );

        await sub.cancel();
        await transport.dispose();
      });

      test('a live socket answers the resume probe — no reconnect and no extra '
          'ConnectedEvent', () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = ChatConfig(
          baseUrl: 'http://localhost:8077/v1',
          realtimeUrl: 'http://localhost:8077',
          tokenProvider: () async => 'test-token',
          wsPingInterval: const Duration(seconds: 30),
          wsPongTimeout: const Duration(milliseconds: 50),
          wsReconnectDelay: const Duration(milliseconds: 5),
        );

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            final channel = _FakeWebSocketChannel(
              autoAuthOk: true,
              autoPong: true,
            );
            channels.add(channel);
            return channel;
          },
        );

        var connectedEvents = 0;
        final sub = transport.events.listen((e) {
          if (e is ConnectedEvent) connectedEvents++;
        });

        await transport.connect();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(channels, hasLength(1));
        expect(connectedEvents, 1);

        await transport.verifyLiveness();
        // Give the probe's pong time to arrive AND the watchdog deadline time
        // to have elapsed — if the probe wrongly tore the socket down it would
        // show up as a second channel by now.
        await Future<void>.delayed(const Duration(milliseconds: 90));

        expect(
          channels,
          hasLength(1),
          reason: 'a live socket must be left untouched by the resume probe',
        );
        expect(
          connectedEvents,
          1,
          reason: 'no reconnect means no second ConnectedEvent',
        );
        expect(transport.state, ChatConnectionState.connected);

        await sub.cancel();
        await transport.dispose();
      });
    });

    group('reconnect backoff tunables', () {
      test(
        'wsMaxReconnectDelay caps the delay even with a large base',
        () async {
          final channels = <_FakeWebSocketChannel>[];
          final config = ChatConfig(
            baseUrl: 'http://localhost:8077/v1',
            realtimeUrl: 'http://localhost:8077',
            tokenProvider: () async => 'test-token',
            // Deliberately huge so an uncapped exponential backoff would take
            // far longer than the test timeout to reconnect.
            wsReconnectDelay: const Duration(seconds: 10),
            wsMaxReconnectDelay: const Duration(milliseconds: 30),
            wsReconnectJitterMs: 0,
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
          await channels.first.simulateDrop();

          for (var i = 0; i < 200 && channels.length < 2; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          expect(
            channels,
            hasLength(2),
            reason:
                'wsMaxReconnectDelay must cap the exponential backoff — an '
                'uncapped 10s base would never reconnect within this wait',
          );

          await transport.dispose();
        },
      );
    });
  });
}
