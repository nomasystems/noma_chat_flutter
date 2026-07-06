import 'dart:async';
import 'dart:convert';

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/realtime_transport.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeChannel implements WebSocketChannel {
  _FakeChannel({bool autoAuthOk = true}) {
    if (autoAuthOk) {
      _stream.onListen = () {
        scheduleMicrotask(() {
          if (!_stream.isClosed) _stream.add(jsonEncode({'type': 'auth_ok'}));
        });
      };
    }
  }

  final _stream = StreamController<dynamic>.broadcast();
  final _sinkController = StreamController<dynamic>(); // ignore: close_sinks
  @override
  // ignore: close_sinks
  late final _FakeSink sink = _FakeSink(_sinkController);

  @override
  Stream<dynamic> get stream => _stream.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void receive(Map<String, dynamic> json) => _stream.add(jsonEncode(json));

  Future<void> drop() async => _stream.close();
}

class _FakeSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final List<String> sent = [];
  _FakeSink(this._controller);

  @override
  void add(dynamic data) {
    sent.add(data as String);
    _controller.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ChatConfig _config() => ChatConfig(
  baseUrl: 'https://api.example.com',
  realtimeUrl: 'https://realtime.example.com',
  tokenProvider: () async => 'test-token',
);

Future<(WsTransport, _FakeChannel)> _connected() async {
  late _FakeChannel channel;
  final transport = WsTransport(
    config: _config(),
    channelFactory: (uri) {
      channel = _FakeChannel();
      return channel;
    },
  );
  await transport.connect();
  await Future<void>.delayed(Duration.zero);
  return (transport, channel);
}

void main() {
  group('WsTransport ack tracking (transport-001)', () {
    test('resolves true when a matching message_acked echoes the ackId',
        () async {
      final (transport, channel) = await _connected();

      final ackFuture = transport.sendMessageAwaitingAck(
        'room-1',
        text: 'hi',
        clientMessageId: 'cmid-1',
      );

      final sentFrame =
          jsonDecode(channel.sink.sent.last) as Map<String, dynamic>;
      // The idempotency key rides as a top-level frame field for backend dedup.
      expect(sentFrame['clientMessageId'], 'cmid-1');
      final ackId =
          (sentFrame['metadata'] as Map<String, dynamic>)[WsTransport.ackIdKey]
              as String;

      channel.receive({
        'type': 'message_acked',
        'roomId': 'room-1',
        'messageId': 'server-1',
        'seq': 1,
        'metadata': {WsTransport.ackIdKey: ackId},
      });

      expect(await ackFuture, isTrue);
      await transport.dispose();
    });

    test('resolves false on ack timeout without losing the awaiter', () async {
      final (transport, _) = await _connected();

      final acked = await transport.sendMessageAwaitingAck(
        'room-1',
        text: 'hi',
        ackTimeout: const Duration(milliseconds: 20),
      );

      expect(acked, isFalse);
      await transport.dispose();
    });

    test('resolves false for every in-flight send when the socket drops',
        () async {
      final (transport, channel) = await _connected();

      final a = transport.sendMessageAwaitingAck('room-1', text: 'a');
      final b = transport.sendMessageAwaitingAck('room-1', text: 'b');

      await channel.drop();
      await Future<void>.delayed(Duration.zero);

      expect(await a, isFalse);
      expect(await b, isFalse);
      await transport.dispose();
    });

    test('does not inject an ackId into the caller-visible send when '
        'disconnected (returns false immediately)', () async {
      final transport = WsTransport(
        config: _config(),
        channelFactory: (uri) => _FakeChannel(autoAuthOk: false),
      );

      expect(await transport.sendMessageAwaitingAck('room-1', text: 'x'),
          isFalse);
      await transport.dispose();
    });
  });

  group('TransportManager event backpressure (realtime-001)', () {
    test('a paused (slow) consumer bounds its backlog to the cap: oldest '
        'events are dropped, newest survive, and a metric is emitted',
        () async {
      final metrics = <String>[];
      final source = StreamController<ChatEvent>.broadcast();
      final manager = TransportManager.fromTransport(
        transport: _StubTransport(source.stream),
        eventBufferSize: 5,
        metricCallback: (metric, _) => metrics.add(metric),
      );
      await manager.connect();

      final received = <ChatEvent>[];
      final sub = manager.events.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      // Pause the subscription (a slow / suspended consumer) and flood far
      // more than the cap. Events queue in the per-listener buffer.
      sub.pause();
      for (var i = 0; i < 1000; i++) {
        source.add(RoomUpdatedEvent(roomId: 'r$i'));
      }
      source.add(const RoomUpdatedEvent(roomId: 'last'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Drop-oldest kicked in well before 1000 events accumulated.
      expect(metrics, contains('event_stream_backpressure_drop'));

      sub.resume();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final rooms =
          received.whereType<RoomUpdatedEvent>().map((e) => e.roomId).toList();
      // The newest event survives the drop-oldest policy.
      expect(rooms.last, equals('last'));
      // The backlog was bounded — far fewer than 1001 events delivered.
      expect(rooms.length, lessThan(1001));
      // Oldest events were the ones dropped.
      expect(rooms, isNot(contains('r0')));

      await sub.cancel();
      await manager.dispose();
      await source.close();
    });

    test('supports multiple independent listeners', () async {
      final source = StreamController<ChatEvent>.broadcast();
      final manager = TransportManager.fromTransport(
        transport: _StubTransport(source.stream),
        eventBufferSize: 5,
      );
      await manager.connect();

      final a = <ChatEvent>[];
      final b = <ChatEvent>[];
      final subA = manager.events.listen(a.add);
      final subB = manager.events.listen(b.add);
      await Future<void>.delayed(Duration.zero);

      source.add(const RoomUpdatedEvent(roomId: 'r1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(a.whereType<RoomUpdatedEvent>().map((e) => e.roomId), ['r1']);
      expect(b.whereType<RoomUpdatedEvent>().map((e) => e.roomId), ['r1']);

      await subA.cancel();
      await subB.cancel();
      await manager.dispose();
      await source.close();
    });
  });
}

class _StubTransport implements RealtimeTransport {
  _StubTransport(this._events);
  final Stream<ChatEvent> _events;

  @override
  Stream<ChatEvent> get events => _events;

  @override
  Stream<ChatConnectionState> get stateChanges => const Stream.empty();

  @override
  ChatConnectionState get state => ChatConnectionState.connected;

  @override
  bool get authTerminated => false;

  @override
  bool get supportsOutboundFrames => false;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> notifyTokenRotated() async {}

  @override
  void sendTyping(String roomId, {String activity = 'startsTyping'}) {}

  @override
  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) {}

  @override
  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) {}

  @override
  void sendDelivered(String roomId, String messageId) {}

  @override
  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) {}

  @override
  Future<bool> sendMessageAwaitingAck(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
    Duration ackTimeout = const Duration(seconds: 5),
  }) async => false;

  @override
  Future<void> refresh({String? singleRoomId}) async {}
}
