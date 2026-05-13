import 'dart:async';
import 'dart:convert';

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel implements WebSocketChannel {
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
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void receiveMessage(String message) => _streamController.add(message);

  List<String> get sentMessages =>
      _sinkController.stream.toList() as List<String>;
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
            fakeChannel.receiveMessage(
                jsonEncode({'type': 'auth_ok'}));
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
            channel.receiveMessage(
                jsonEncode({'type': 'auth_ok'}));
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
            channel.receiveMessage(
                jsonEncode({'type': 'auth_ok'}));
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
            channel.receiveMessage(
                jsonEncode({'type': 'auth_ok'}));
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
            channel.receiveMessage(
                jsonEncode({'type': 'auth_ok'}));
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

      fakeChannel.receiveMessage(jsonEncode({
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
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
        'type': 'room_deleted',
        'roomId': 'room-2',
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
        'type': 'event',
        'data': null,
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
        'type': 'event',
        'data': 'string_data',
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
        'type': 'event',
        'data': {
          'type': 'totally_unknown',
          'foo': 'bar',
        },
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
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
      }));

      fakeChannel.receiveMessage(jsonEncode({
        'type': 'new_message',
        'roomId': 'room-1',
        'message': {
          'id': 'msg-2',
          'from': 'user-1',
          'text': 'Second',
          'timestamp': '2026-01-01T00:00:01Z',
        },
      }));

      fakeChannel.receiveMessage(jsonEncode({
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
      }));

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

      fakeChannel.receiveMessage(jsonEncode({
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
      }));

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
  });
}
