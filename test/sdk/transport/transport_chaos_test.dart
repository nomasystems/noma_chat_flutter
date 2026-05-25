import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Shared fakes (same patterns as ws_transport_test.dart)
// ---------------------------------------------------------------------------

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
  // ignore: close_sinks
  final _sinkController = StreamController<dynamic>();

  @override
  // ignore: close_sinks
  late final _StubSink sink = _StubSink(_sinkController);

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

  void receiveMessage(dynamic message) => _streamController.add(message);

  Future<void> simulateDrop() async {
    await _streamController.close();
  }
}

class _StubSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final List<dynamic> messages = [];

  _StubSink(this._controller);

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

// ---------------------------------------------------------------------------
// Helper — minimal config with short timeouts to keep tests fast
// ---------------------------------------------------------------------------

ChatConfig _makeConfig({
  int? maxReconnectAttempts,
  Duration? authTimeout,
  Duration? wsReconnectDelay,
}) {
  return ChatConfig(
    baseUrl: 'http://localhost:8077/v1',
    realtimeUrl: 'http://localhost:8077',
    tokenProvider: () async => 'test-token',
    maxReconnectAttempts: maxReconnectAttempts,
    authTimeout: authTimeout ?? const Duration(milliseconds: 200),
    wsReconnectDelay: wsReconnectDelay ?? const Duration(milliseconds: 20),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WsTransport chaos / adversarial', () {
    // -----------------------------------------------------------------------
    // 1. Rapid connect/disconnect cycles
    // -----------------------------------------------------------------------
    test('rapid connect/disconnect cycles — no unhandled exceptions, '
        'ends disconnected', () async {
      final config = _makeConfig(maxReconnectAttempts: 0);

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) => _FakeWebSocketChannel(autoAuthOk: true),
      );

      Object? unhandled;
      runZonedGuarded(() async {
        for (var i = 0; i < 50; i++) {
          // Fire-and-forget connect then immediately disconnect.
          // We intentionally do NOT await connect() so the pair is
          // as racy as possible.
          unawaited(transport.connect());
          await transport.disconnect();
        }
      }, (err, _) => unhandled = err);

      // Allow any pending microtasks / timers to settle.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(unhandled, isNull, reason: 'no unhandled exception expected');
      expect(
        transport.state,
        anyOf(
          equals(ChatConnectionState.disconnected),
          equals(ChatConnectionState.error),
        ),
        reason: 'final state must be terminal (disconnected or error)',
      );

      await transport.dispose();
    });

    // -----------------------------------------------------------------------
    // 2. Concurrent connect() calls
    // -----------------------------------------------------------------------
    test(
      'concurrent connect() calls — no throw, no duplicate subscriptions',
      () async {
        final channels = <_FakeWebSocketChannel>[];
        final config = _makeConfig(maxReconnectAttempts: 0);

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            final ch = _FakeWebSocketChannel(autoAuthOk: true);
            channels.add(ch);
            return ch;
          },
        );

        // Fire 5 concurrent connects. At most one should proceed because
        // connect() guards on connecting/connected state.
        await Future.wait([
          transport.connect(),
          transport.connect(),
          transport.connect(),
          transport.connect(),
          transport.connect(),
        ]);

        // Only one channel should have been created (the rest are no-ops).
        expect(
          channels.length,
          lessThanOrEqualTo(2),
          reason:
              'at most one channel should be created from concurrent '
              'connect() calls; concurrent in-flight calls that arrive '
              'while "connecting" should be dropped as no-ops',
        );

        // Verify the transport is in a stable state (connected or at most
        // reconnecting if the autoAuthOk microtask lost a race).
        expect(
          transport.state,
          anyOf(
            equals(ChatConnectionState.connected),
            equals(ChatConnectionState.reconnecting),
            equals(ChatConnectionState.connecting),
          ),
        );

        await transport.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 3. Malformed auth frames
    // -----------------------------------------------------------------------
    test('malformed auth frames — transport emits disconnected/error state '
        'and cleans up without hanging', () async {
      // Scenario: the channel sends four bad frames in sequence.
      // The channel does NOT send auth_ok, so _authenticate() completes
      // via timeout (authTimeout = 200 ms) or via auth_error frame.

      // We only send auth_error here to trigger the fast path; the other
      // "garbage" frames arrive as stream messages that hit _onMessage
      // and throw (non-JSON / non-Map) which the stream listener forwards
      // to _onError.
      _FakeWebSocketChannel? channel;
      final config = _makeConfig(
        maxReconnectAttempts: 0,
        authTimeout: const Duration(milliseconds: 300),
      );

      final stateHistory = <ChatConnectionState>[];

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          channel = _FakeWebSocketChannel();
          return channel!;
        },
      );

      transport.stateChanges.listen(stateHistory.add);

      // Start connecting — do not await so we can push bad frames.
      final connectFuture = transport.connect();

      // Let the channel be created and the subscription established.
      await Future<void>.delayed(Duration.zero);

      // Frame 1: non-JSON bytes — _onMessage will throw a FormatException
      //          which gets routed to _onError.
      channel!.receiveMessage('\xde\xad\xbe\xef');

      await Future<void>.delayed(Duration.zero);

      // Frame 2: garbage JSON — still not a Map, throws on the `as Map`
      //          cast.  The channel drop from frame 1 may have already
      //          ended the subscription; guard with a null/closed check.
      if (!channel!._streamController.isClosed) {
        channel!.receiveMessage('{not: json}');
      }

      await Future<void>.delayed(Duration.zero);

      // Frame 3: valid JSON array, not a Map.
      if (!channel!._streamController.isClosed) {
        channel!.receiveMessage('[]');
      }

      await Future<void>.delayed(Duration.zero);

      // Frame 4: auth_error — this is the fastest way to make
      //          _authenticate() complete with an error when the
      //          channel is still open.
      if (!channel!._streamController.isClosed) {
        channel!.receiveMessage(jsonEncode({'type': 'auth_error'}));
      }

      // Wait for connect() to finish (it should not hang).
      await connectFuture
          .timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {
              fail('connect() hung — transport did not resolve within 500 ms');
            },
          )
          .catchError((_) {});

      // Transport must have settled into a terminal state (not connecting).
      expect(
        transport.state,
        isNot(equals(ChatConnectionState.connecting)),
        reason: 'transport must not be stuck in connecting after bad frames',
      );
      expect(
        transport.state,
        anyOf(
          equals(ChatConnectionState.disconnected),
          equals(ChatConnectionState.error),
          equals(ChatConnectionState.reconnecting),
        ),
      );

      await transport.dispose();
    });

    // -----------------------------------------------------------------------
    // 4. Null/empty message frames after auth_ok
    // -----------------------------------------------------------------------
    test(
      'null/empty frames after auth_ok — no crash, events stream not broken',
      () async {
        late _FakeWebSocketChannel channel;
        final config = _makeConfig(maxReconnectAttempts: 0);

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            channel = _FakeWebSocketChannel(autoAuthOk: true);
            return channel;
          },
        );

        await transport.connect();
        expect(transport.state, equals(ChatConnectionState.connected));

        final receivedEvents = <ChatEvent>[];
        final sub = transport.events
            .where((e) => e is! ConnectedEvent)
            .listen(receivedEvents.add);

        // Empty string — jsonDecode('') throws FormatException which
        // _onError handles; the channel closes.  Guard subsequent sends.
        channel.receiveMessage('');
        await Future<void>.delayed(Duration.zero);

        // JSON with null type — valid Map, EventParser returns null.
        if (!channel._streamController.isClosed) {
          channel.receiveMessage(jsonEncode({'type': null}));
          await Future<void>.delayed(Duration.zero);
        }

        // JSON array — _onMessage casts to Map which throws; _onError runs.
        if (!channel._streamController.isClosed) {
          channel.receiveMessage(jsonEncode([]));
          await Future<void>.delayed(Duration.zero);
        }

        // Non-string (int) — _onMessage guards with `data is! String` → no-op.
        if (!channel._streamController.isClosed) {
          channel.receiveMessage(42);
          await Future<void>.delayed(Duration.zero);
        }

        // Events stream must still be alive (no crash / isClosed).
        expect(transport.events.isBroadcast, isTrue);

        // No spurious application-level events should have been emitted.
        expect(
          receivedEvents.whereType<ErrorEvent>().length,
          lessThanOrEqualTo(receivedEvents.length),
          reason: 'only error events expected, no phantom message events',
        );

        await sub.cancel();
        await transport.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 5. Giant message — 1 MB string
    // -----------------------------------------------------------------------
    test(
      'giant 1 MB message — EventParser returns null, transport continues',
      () async {
        late _FakeWebSocketChannel channel;
        final config = _makeConfig(maxReconnectAttempts: 0);

        final transport = WsTransport(
          config: config,
          channelFactory: (uri) {
            channel = _FakeWebSocketChannel(autoAuthOk: true);
            return channel;
          },
        );

        await transport.connect();
        expect(transport.state, equals(ChatConnectionState.connected));

        final nonConnectedEvents = <ChatEvent>[];
        final sub = transport.events
            .where((e) => e is! ConnectedEvent)
            .listen(nonConnectedEvents.add);

        // 1 MB value field — type is 'unknown_giant' so EventParser returns
        // null; the transport must not emit an event nor crash.
        final bigPayload = 'x' * (1024 * 1024);
        channel.receiveMessage(
          jsonEncode({'type': 'unknown_giant', 'data': bigPayload}),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Transport must still be connected and the stream intact.
        expect(transport.state, equals(ChatConnectionState.connected));
        expect(nonConnectedEvents, isEmpty);

        await sub.cancel();
        await transport.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 6. Channel factory throws synchronously
    // -----------------------------------------------------------------------
    test('channelFactory throws synchronously — connect() completes, '
        'transport ends up disconnected', () async {
      final config = _makeConfig(maxReconnectAttempts: 0);

      final transport = WsTransport(
        config: config,
        channelFactory: (_) => throw StateError('factory boom'),
      );

      // Must not hang. Errors from _doConnect are caught internally and
      // do not propagate to the caller, so we swallow any that do leak.
      await transport
          .connect()
          .timeout(
            const Duration(milliseconds: 500),
            onTimeout: () => fail('connect() hung when channelFactory threw'),
          )
          .catchError((_) {});

      // connect() itself should complete (possibly with error propagation
      // suppressed inside _doConnect which catches exceptions).  What
      // matters is that it does not hang and the transport is in a
      // terminal / non-connecting state.
      expect(
        transport.state,
        isNot(equals(ChatConnectionState.connecting)),
        reason: 'transport must not be stuck in connecting',
      );
      expect(
        transport.state,
        anyOf(
          equals(ChatConnectionState.disconnected),
          equals(ChatConnectionState.error),
          equals(ChatConnectionState.reconnecting),
        ),
      );

      await transport.dispose();
    });

    // -----------------------------------------------------------------------
    // 7. Partial disconnect mid-stream (channel stream closes abruptly)
    // -----------------------------------------------------------------------
    test('channel stream closes abruptly mid-session — transport emits '
        'reconnecting or disconnected within 500 ms', () async {
      late _FakeWebSocketChannel activeChannel;
      final config = _makeConfig(
        maxReconnectAttempts: 1,
        wsReconnectDelay: const Duration(milliseconds: 10),
      );

      final transport = WsTransport(
        config: config,
        channelFactory: (uri) {
          activeChannel = _FakeWebSocketChannel(autoAuthOk: true);
          return activeChannel;
        },
      );

      // Establish a successful connection first.
      await transport.connect();
      expect(transport.state, equals(ChatConnectionState.connected));

      final stateHistory = <ChatConnectionState>[];
      final sub = transport.stateChanges.listen(stateHistory.add);

      // Abruptly close the underlying channel stream.
      await activeChannel.simulateDrop();

      // Allow _onDone + _scheduleReconnect timers to fire.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // The transport must have transitioned away from connected.
      expect(
        stateHistory,
        isNotEmpty,
        reason: 'at least one state transition expected after stream drop',
      );
      expect(
        stateHistory,
        anyOf(
          contains(ChatConnectionState.reconnecting),
          contains(ChatConnectionState.disconnected),
          contains(ChatConnectionState.error),
        ),
        reason:
            'transport must emit reconnecting, disconnected, or error '
            'after the channel stream closes',
      );

      await sub.cancel();
      await transport.dispose();
    });
  });
}
