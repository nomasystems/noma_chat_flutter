import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/auth_interceptor.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({
    this.closeCode,
    bool autoAuthOk = false,
    String? firstMessage,
  }) {
    final first = autoAuthOk ? jsonEncode({'type': 'auth_ok'}) : firstMessage;
    if (first != null) {
      _sc.onListen = () {
        scheduleMicrotask(() {
          if (!_sc.isClosed) _sc.add(first);
        });
      };
    }
  }

  final _sc = StreamController<dynamic>.broadcast();
  // ignore: close_sinks — test fake; nothing to release.
  final _fakeSink = _FakeWebSocketSink();

  @override
  final int? closeCode;
  @override
  String? get closeReason => null;
  @override
  // ignore: close_sinks
  WebSocketSink get sink => _fakeSink;
  _FakeWebSocketSink get fakeSink => _fakeSink;
  @override
  Stream<dynamic> get stream => _sc.stream;
  @override
  Future<void> get ready => Future.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void push(dynamic message) {
    if (!_sc.isClosed) _sc.add(message);
  }

  Future<void> drop() => _sc.close();
}

class _FailingReadyChannel implements WebSocketChannel {
  @override
  Future<void> get ready => Future.error(Exception('connection refused'));
  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();
  @override
  // ignore: close_sinks
  WebSocketSink get sink => _NullSink();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NullSink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TrackingAuthInterceptor extends AuthInterceptor {
  _TrackingAuthInterceptor({
    String token = 'test-token',
    bool shouldThrow = false,
  }) : _token = token,
       _shouldThrow = shouldThrow;

  final String _token;
  final bool _shouldThrow;
  int invalidateCalls = 0;

  @override
  Future<String> getAuthHeader() async {
    if (_shouldThrow) throw Exception('token provider failed');
    return 'Bearer $_token';
  }

  @override
  void invalidateCache() => invalidateCalls++;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ChatConfig _config({
  _TrackingAuthInterceptor? auth,
  Duration authTimeout = const Duration(seconds: 10),
  Duration wsReconnectDelay = const Duration(seconds: 2),
  int? maxReconnectAttempts,
}) {
  return ChatConfig.withAuthInterceptor(
    baseUrl: 'https://api.example.com',
    realtimeUrl: 'https://realtime.example.com',
    authInterceptor: auth ?? _TrackingAuthInterceptor(),
    authTimeout: authTimeout,
    wsReconnectDelay: wsReconnectDelay,
    maxReconnectAttempts: maxReconnectAttempts,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WsTransport — auth timeout', () {
    test('error state when auth_ok never arrives within authTimeout', () async {
      final errorStateReceived = Completer<void>();

      final transport = WsTransport(
        config: _config(authTimeout: const Duration(milliseconds: 20)),
        channelFactory: (_) => _FakeWebSocketChannel(),
      );

      final sub = transport.stateChanges.listen((state) {
        if (state == ChatConnectionState.error &&
            !errorStateReceived.isCompleted) {
          errorStateReceived.complete();
        }
      });

      unawaited(transport.connect());

      await errorStateReceived.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('error state never reached after auth timeout'),
      );

      await sub.cancel();
      await transport.dispose();
    });
  });

  group('WsTransport — auth_error message', () {
    test(
      'emits error event and invalidates token cache on auth_error',
      () async {
        final auth = _TrackingAuthInterceptor();
        final errors = <ChatEvent>[];

        final transport = WsTransport(
          config: _config(auth: auth),
          channelFactory: (_) => _FakeWebSocketChannel(
            firstMessage: jsonEncode({
              'type': 'auth_error',
              'reason': 'invalid',
            }),
          ),
        );
        final sub = transport.events
            .where((e) => e is ErrorEvent)
            .listen(errors.add);

        await transport.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        await transport.dispose();

        expect(errors, isNotEmpty);
        final err = errors.first as ErrorEvent;
        expect(err.exception, isA<ChatAuthException>());
        expect(auth.invalidateCalls, greaterThanOrEqualTo(1));
      },
    );
  });

  group('WsTransport — token fetch failure', () {
    test('error state when getToken() throws during auth', () async {
      final auth = _TrackingAuthInterceptor(shouldThrow: true);
      final states = <ChatConnectionState>[];

      final transport = WsTransport(
        config: _config(auth: auth, authTimeout: const Duration(seconds: 5)),
        channelFactory: (_) => _FakeWebSocketChannel(),
      );
      final stateSub = transport.stateChanges.listen(states.add);

      await transport.connect().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await stateSub.cancel();
      await transport.dispose();

      expect(states, contains(ChatConnectionState.error));
    });
  });

  group('WsTransport — connect() while connecting', () {
    test(
      'second connect() while connecting is a no-op (single channel)',
      () async {
        final channels = <_FakeWebSocketChannel>[];
        final transport = WsTransport(
          config: _config(),
          channelFactory: (_) {
            final ch = _FakeWebSocketChannel();
            channels.add(ch);
            return ch;
          },
        );

        // Start connecting but don't await (never sends auth_ok)
        unawaited(
          transport.connect().timeout(
            const Duration(milliseconds: 200),
            onTimeout: () {},
          ),
        );

        // Attempt a second connect while the first is in-flight
        await Future<void>.delayed(const Duration(milliseconds: 5));
        unawaited(
          transport.connect().timeout(
            const Duration(milliseconds: 200),
            onTimeout: () {},
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 250));
        await transport.dispose();

        expect(channels, hasLength(1));
      },
    );
  });

  group('WsTransport — _onMessage: control frames', () {
    late _FakeWebSocketChannel channel;
    late WsTransport transport;

    setUp(() async {
      channel = _FakeWebSocketChannel(autoAuthOk: true);
      transport = WsTransport(
        config: _config(),
        channelFactory: (_) => channel,
      );
      await transport.connect();
    });

    tearDown(() => transport.dispose());

    test('pong frame produces no application event', () async {
      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      channel.push(jsonEncode({'type': 'pong'}));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(events, isEmpty);
    });

    test('auth_refreshed frame produces no application event', () async {
      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      channel.push(
        jsonEncode({'type': 'auth_refreshed', 'expiresAt': '2027-01-01'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(events, isEmpty);
    });

    test('auth_refresh_error invalidates token cache', () async {
      final auth = _TrackingAuthInterceptor();
      final authChannel = _FakeWebSocketChannel(autoAuthOk: true);
      final t = WsTransport(
        config: _config(auth: auth),
        channelFactory: (_) => authChannel,
      );
      await t.connect();

      authChannel.push(
        jsonEncode({'type': 'auth_refresh_error', 'code': 'expired'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await t.dispose();

      expect(auth.invalidateCalls, greaterThanOrEqualTo(1));
    });

    test('error frame emits ChatWsOperationException', () async {
      final errors = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is ErrorEvent)
          .listen(errors.add);

      channel.push(
        jsonEncode({
          'type': 'error',
          'reason': 'forbidden',
          'action': 'send_message',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(errors, hasLength(1));
      final err = errors.first as ErrorEvent;
      expect(err.exception, isA<ChatWsOperationException>());
    });

    test('non-string data is silently ignored', () async {
      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      // Push a raw integer, not a String
      channel.push(42);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(events, isEmpty);
    });

    test('invalid JSON string is silently ignored', () async {
      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      channel.push('{not: valid json}');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(events, isEmpty);
    });

    test('JSON array (non-map) is silently ignored', () async {
      final events = <ChatEvent>[];
      final sub = transport.events
          .where((e) => e is! ConnectedEvent)
          .listen(events.add);

      channel.push('[1, 2, 3]');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();
      expect(events, isEmpty);
    });
  });

  group('WsTransport — _onDone: clean disconnect', () {
    test(
      'explicit disconnect() yields disconnected state without reconnect',
      () async {
        final channel = _FakeWebSocketChannel(autoAuthOk: true);
        final states = <ChatConnectionState>[];
        final transport = WsTransport(
          config: _config(),
          channelFactory: (_) => channel,
        );
        final sub = transport.stateChanges.listen(states.add);

        await transport.connect();
        await transport.disconnect();

        await Future<void>.delayed(const Duration(milliseconds: 30));
        await sub.cancel();
        await transport.dispose();

        expect(states.last, ChatConnectionState.disconnected);
        // Must NOT contain reconnecting after a voluntary disconnect
        expect(states, isNot(contains(ChatConnectionState.reconnecting)));
      },
    );
  });

  group('WsTransport — _onDone: token invalidation close codes', () {
    for (final code in [4003, 4004]) {
      test('close code $code invalidates token cache', () async {
        final auth = _TrackingAuthInterceptor();
        final closingChannel = _FakeWebSocketChannel(
          autoAuthOk: true,
          closeCode: code,
        );
        final transport = WsTransport(
          config: _config(
            auth: auth,
            wsReconnectDelay: const Duration(milliseconds: 5),
          ),
          channelFactory: (_) => closingChannel,
        );

        await transport.connect();
        final invalidatesBefore = auth.invalidateCalls;
        await closingChannel.drop();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await transport.dispose();
        expect(auth.invalidateCalls, greaterThan(invalidatesBefore));
      });
    }

    test(
      'close code 4005 is terminal: no reconnect, emits auth error',
      () async {
        final auth = _TrackingAuthInterceptor();
        final closingChannel = _FakeWebSocketChannel(
          autoAuthOk: true,
          closeCode: 4005,
        );
        final transport = WsTransport(
          config: _config(
            auth: auth,
            wsReconnectDelay: const Duration(milliseconds: 5),
          ),
          channelFactory: (_) => closingChannel,
        );
        final states = <ChatConnectionState>[];
        final events = <ChatEvent>[];
        final ss = transport.stateChanges.listen(states.add);
        final es = transport.events.listen(events.add);

        await transport.connect();
        await closingChannel.drop();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Terminal: ends in error, never schedules a reconnect.
        expect(transport.state, ChatConnectionState.error);
        expect(states, isNot(contains(ChatConnectionState.reconnecting)));
        // Surfaces a TERMINAL auth error and drops the cached token. The
        // terminal flag is what lets AutoFailoverTransport suspend the SSE
        // fallback instead of replaying the rejected token.
        expect(
          events.whereType<ErrorEvent>().any(
            (e) =>
                e.exception is ChatAuthException &&
                (e.exception as ChatAuthException).terminal,
          ),
          isTrue,
        );
        expect(auth.invalidateCalls, greaterThan(0));

        await ss.cancel();
        await es.cancel();
        await transport.dispose();
      },
    );
  });

  group('WsTransport — _scheduleReconnect: max attempts', () {
    test(
      'stops reconnecting and emits error after maxReconnectAttempts',
      () async {
        final List<_FakeWebSocketChannel> channels = [];
        final maxReconnectReceived = Completer<void>();

        // First channel: auth_ok so initial connect succeeds.
        // Subsequent channels: send auth_error so reconnects fail fast.
        int callCount = 0;
        final transport = WsTransport(
          config: _config(
            wsReconnectDelay: const Duration(milliseconds: 10),
            maxReconnectAttempts: 1,
            authTimeout: const Duration(seconds: 5),
          ),
          channelFactory: (_) {
            callCount++;
            final ch = _FakeWebSocketChannel(
              autoAuthOk: callCount == 1,
              firstMessage: callCount > 1
                  ? jsonEncode({'type': 'auth_error'})
                  : null,
            );
            channels.add(ch);
            return ch;
          },
        );

        final sub = transport.events.where((e) => e is ErrorEvent).listen((e) {
          final err = e as ErrorEvent;
          if (err.exception is ChatNetworkException &&
              err.exception.toString().contains('Max reconnect') &&
              !maxReconnectReceived.isCompleted) {
            maxReconnectReceived.complete();
          }
        });

        await transport.connect();
        expect(transport.state, ChatConnectionState.connected);

        await channels.first.drop();

        await maxReconnectReceived.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('max-reconnect error never emitted'),
        );

        await sub.cancel();
        await transport.dispose();
      },
    );
  });

  group('WsTransport — sendAuthRefresh', () {
    test('sends auth_refresh frame while connected', () async {
      final channel = _FakeWebSocketChannel(autoAuthOk: true);
      final transport = WsTransport(
        config: _config(),
        channelFactory: (_) => channel,
      );
      await transport.connect();

      await transport.sendAuthRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await transport.dispose();

      final authRefreshFrames = channel.fakeSink.sent
          .whereType<String>()
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'auth_refresh')
          .toList();
      expect(authRefreshFrames, hasLength(1));
    });

    test('sendAuthRefresh while disconnected is a no-op', () async {
      final transport = WsTransport(
        config: _config(),
        channelFactory: (_) => _FakeWebSocketChannel(),
      );
      // Never connect — just call sendAuthRefresh; must not throw.
      await expectLater(transport.sendAuthRefresh(), completes);
      await transport.dispose();
    });

    test('notifyTokenRotated delegates to sendAuthRefresh', () async {
      final channel = _FakeWebSocketChannel(autoAuthOk: true);
      final transport = WsTransport(
        config: _config(),
        channelFactory: (_) => channel,
      );
      await transport.connect();

      await transport.notifyTokenRotated();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await transport.dispose();

      final frames = channel.fakeSink.sent
          .whereType<String>()
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'auth_refresh')
          .toList();
      expect(frames, hasLength(1));
    });
  });

  group('WsTransport — connection failure (ready throws)', () {
    test('enters error state when channel.ready throws', () async {
      final states = <ChatConnectionState>[];
      final transport = WsTransport(
        config: _config(wsReconnectDelay: const Duration(seconds: 60)),
        channelFactory: (_) => _FailingReadyChannel(),
      );
      final sub = transport.stateChanges.listen(states.add);

      await transport.connect().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();
      await transport.dispose();

      expect(states, contains(ChatConnectionState.error));
    });
  });
}
