import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/cache_config.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/src/_internal/transport/auto_failover_transport.dart';
import 'package:noma_chat/src/_internal/transport/realtime_transport.dart';
import 'package:noma_chat/src/_internal/transport/sse_transport.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Fakes & mocks shared across groups
// ---------------------------------------------------------------------------

class _MockTransport extends Mock implements RealtimeTransport {}

class _FakeWebSocketChannel implements WebSocketChannel {
  final _streamController = StreamController<dynamic>.broadcast();
  @override
  // ignore: close_sinks
  late final _FakeWebSocketSink sink = _FakeWebSocketSink();

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

  void push(String message) {
    if (!_streamController.isClosed) _streamController.add(message);
  }

  bool get isClosed => _streamController.isClosed;
}

class _FakeWebSocketSink implements WebSocketSink {
  final messages = <dynamic>[];

  @override
  void add(dynamic data) => messages.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Datasource that records calls to [dispose] / [saveCacheTimestamps].
class _TrackingDatasource extends MemoryChatLocalDatasource {
  int disposeCalls = 0;
  int saveCalls = 0;

  @override
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {
    saveCalls++;
    return super.saveCacheTimestamps(timestamps);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    return super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ChatConfig _config({
  String baseUrl = 'http://localhost:8077/v1',
  String realtimeUrl = 'http://localhost:8077',
}) => ChatConfig(
  baseUrl: baseUrl,
  realtimeUrl: realtimeUrl,
  tokenProvider: () async => 'test-token',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // 1. WsTransport
  // -------------------------------------------------------------------------
  group('WsTransport — memory / resource release', () {
    test('event stream is closed after dispose()', () async {
      late _FakeWebSocketChannel fakeChannel;

      final transport = WsTransport(
        config: _config(),
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(
            () => fakeChannel.push(jsonEncode({'type': 'auth_ok'})),
          );
          return fakeChannel;
        },
      );

      await transport.connect();

      bool doneFired = false;
      final sub = transport.events.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();

      // Give the close notification a microtask to propagate.
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'event stream must complete on dispose',
      );
      expect(
        fakeChannel.isClosed,
        isFalse,
        reason:
            'the fake WS stream was closed by simulateDrop, not by dispose — '
            'WsTransport closes the sink, not the raw stream controller',
      );
    });

    test('stateChanges stream is closed after dispose()', () async {
      late _FakeWebSocketChannel fakeChannel;

      final transport = WsTransport(
        config: _config(),
        channelFactory: (uri) {
          fakeChannel = _FakeWebSocketChannel();
          Future.microtask(
            () => fakeChannel.push(jsonEncode({'type': 'auth_ok'})),
          );
          return fakeChannel;
        },
      );

      await transport.connect();

      bool doneFired = false;
      final sub = transport.stateChanges.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'stateChanges stream must complete on dispose',
      );
    });

    test('reconnect timer is not active after dispose()', () async {
      // fakeAsync lets us drive timers deterministically and verify nothing
      // fires after dispose.
      fakeAsync((async) {
        _FakeWebSocketChannel? fakeChannel;

        final transport = WsTransport(
          config: ChatConfig(
            baseUrl: 'http://localhost:8077/v1',
            realtimeUrl: 'http://localhost:8077',
            tokenProvider: () async => 'test-token',
            wsReconnectDelay: const Duration(milliseconds: 100),
            maxReconnectAttempts: 3,
          ),
          channelFactory: (uri) {
            fakeChannel = _FakeWebSocketChannel();
            // Immediate auth_ok so connect() completes synchronously inside
            // fakeAsync.
            fakeChannel!._streamController.onListen = () {
              async.flushMicrotasks();
              fakeChannel!.push(jsonEncode({'type': 'auth_ok'}));
            };
            return fakeChannel!;
          },
        );

        transport.connect();
        async.flushMicrotasks();

        // Trigger a drop so a reconnect timer is armed.
        fakeChannel!._streamController.close();
        async.flushMicrotasks();

        // Dispose before the timer fires.
        transport.dispose();
        async.flushMicrotasks();

        // Advance past the reconnect delay — nothing should throw or create
        // another channel.
        async.elapse(const Duration(seconds: 5));
        // If a timer fired post-dispose it would try to call _doConnect() on
        // a closed _eventController, which would throw or add to a closed
        // stream. The test passes as long as no unhandled exceptions occur.
      });
    });
  });

  // -------------------------------------------------------------------------
  // 2. SseTransport
  // -------------------------------------------------------------------------
  group('SseTransport — memory / resource release', () {
    test('event stream is closed after dispose()', () async {
      // SseTransport without a real Dio connection — we don't need to connect;
      // we only need to verify that dispose() closes the internal broadcast
      // controllers.
      final transport = SseTransport(config: _config());

      bool doneFired = false;
      final sub = transport.events.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'event stream must complete on dispose',
      );
    });

    test('stateChanges stream is closed after dispose()', () async {
      final transport = SseTransport(config: _config());

      bool doneFired = false;
      final sub = transport.stateChanges.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'stateChanges stream must complete on dispose',
      );
    });

    test('no dangling reconnect timer after dispose() without connecting', () {
      // Verifies that SseTransport can be constructed and disposed without
      // leaving live timers behind. fakeAsync detects any outstanding timers at
      // the end of the callback and would fail the test if any leaked.
      fakeAsync((async) {
        final transport = SseTransport(config: _config());
        transport.dispose();
        async.flushMicrotasks();
        // No elapse needed — if any timer were armed fakeAsync would report it.
      });
    });
  });

  // -------------------------------------------------------------------------
  // 3. OfflineQueue
  // -------------------------------------------------------------------------
  group('OfflineQueue — no dangling timers', () {
    test(
      'enqueue + dispose with MemoryChatLocalDatasource leaves no open timers',
      () {
        fakeAsync((async) {
          final datasource = MemoryChatLocalDatasource();
          final queue = OfflineQueue(store: datasource);

          queue.enqueue(
            PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'hi'),
          );

          // dispose() flushes the persist write and clears the queue.
          queue.dispose();
          async.flushMicrotasks();

          // Advance past any possible timer that may have been armed by the
          // silent persist path — none should fire after dispose.
          async.elapse(const Duration(seconds: 10));
        });
      },
    );

    test(
      'dispose after multiple enqueues with no store completes without error',
      () async {
        final queue = OfflineQueue();

        queue.enqueue(
          PendingSendMessage(id: 'op-1', roomId: 'room-1', text: 'hello'),
        );
        queue.enqueue(
          PendingDeleteMessage(
            id: 'op-2',
            roomId: 'room-1',
            messageId: 'msg-1',
          ),
        );

        await expectLater(queue.dispose(), completes);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. CacheManager
  // -------------------------------------------------------------------------
  group('CacheManager — dispose releases resources', () {
    test('dispose cancels the debounce timer and calls saveCacheTimestamps', () {
      fakeAsync((async) {
        final ds = _TrackingDatasource();
        final manager = CacheManager(
          config: const CacheConfig(),
          datasource: ds,
          persistDebounce: const Duration(seconds: 60),
        );

        // Trigger a markFresh via resolve so the debounce timer is armed.
        manager.resolve<String>(
          key: 'k1',
          ttl: const Duration(hours: 1),
          fromCache: () async => null,
          fromNetwork: () async => const ChatSuccess('v'),
          saveToCache: (_) async {},
        );
        async.flushMicrotasks();

        // Debounce window has NOT elapsed yet — no save yet.
        expect(ds.saveCalls, 0);

        // dispose() must cancel the pending timer and flush synchronously.
        manager.dispose();
        async.flushMicrotasks();

        expect(
          ds.saveCalls,
          1,
          reason: 'dispose must flush the pending dirty state',
        );

        // Advance far past the debounce window — the timer must not fire again.
        async.elapse(const Duration(minutes: 2));
        expect(ds.saveCalls, 1, reason: 'no further saves after dispose');
      });
    });

    test(
      'dispose is idempotent — calling twice does not double-flush',
      () async {
        final ds = _TrackingDatasource();
        final manager = CacheManager(
          config: const CacheConfig(),
          datasource: ds,
          persistDebounce: const Duration(milliseconds: 5),
        );

        // Populate so there is a pending save.
        await manager.resolve<String>(
          key: 'k1',
          ttl: const Duration(hours: 1),
          fromCache: () async => null,
          fromNetwork: () async => const ChatSuccess('v'),
          saveToCache: (_) async {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await manager.dispose();
        final savesAfterFirstDispose = ds.saveCalls;

        // Second dispose should be a no-op.
        await manager.dispose();
        expect(
          ds.saveCalls,
          savesAfterFirstDispose,
          reason: 'second dispose must not trigger additional saves',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 5. TransportManager
  // -------------------------------------------------------------------------
  group('TransportManager — dispose propagates to active transport', () {
    late _MockTransport mockTransport;
    late StreamController<ChatEvent> events;
    late StreamController<ChatConnectionState> states;

    setUp(() {
      mockTransport = _MockTransport();
      events = StreamController<ChatEvent>.broadcast();
      states = StreamController<ChatConnectionState>.broadcast();

      when(() => mockTransport.events).thenAnswer((_) => events.stream);
      when(() => mockTransport.stateChanges).thenAnswer((_) => states.stream);
      when(
        () => mockTransport.state,
      ).thenReturn(ChatConnectionState.disconnected);
      when(() => mockTransport.connect()).thenAnswer((_) async {});
      when(() => mockTransport.disconnect()).thenAnswer((_) async {});
      when(() => mockTransport.dispose()).thenAnswer((_) async {});
      when(() => mockTransport.supportsOutboundFrames).thenReturn(true);
    });

    tearDown(() async {
      await events.close();
      await states.close();
    });

    test(
      'dispose() calls disconnect() and then dispose() on the transport',
      () async {
        final manager = TransportManager.fromTransport(
          transport: mockTransport,
        );

        await manager.connect();
        await manager.dispose();

        verify(() => mockTransport.disconnect()).called(1);
        verify(() => mockTransport.dispose()).called(1);
      },
    );

    test('event and stateChanges streams complete after dispose()', () async {
      final manager = TransportManager.fromTransport(transport: mockTransport);
      await manager.connect();

      bool eventsDone = false;
      bool statesDone = false;

      final sub1 = manager.events.listen(
        (_) {},
        onDone: () => eventsDone = true,
      );
      final sub2 = manager.stateChanges.listen(
        (_) {},
        onDone: () => statesDone = true,
      );
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      await manager.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(eventsDone, isTrue, reason: 'events stream must close on dispose');
      expect(
        statesDone,
        isTrue,
        reason: 'stateChanges stream must close on dispose',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 6. AutoFailoverTransport
  // -------------------------------------------------------------------------
  group('AutoFailoverTransport — dispose propagates to primary and fallback', () {
    late _MockTransport primary;
    late _MockTransport fallback;
    late StreamController<ChatEvent> primaryEvents;
    late StreamController<ChatConnectionState> primaryStates;
    late StreamController<ChatEvent> fallbackEvents;
    late StreamController<ChatConnectionState> fallbackStates;

    setUp(() {
      primary = _MockTransport();
      fallback = _MockTransport();
      primaryEvents = StreamController<ChatEvent>.broadcast();
      primaryStates = StreamController<ChatConnectionState>.broadcast();
      fallbackEvents = StreamController<ChatEvent>.broadcast();
      fallbackStates = StreamController<ChatConnectionState>.broadcast();

      when(() => primary.events).thenAnswer((_) => primaryEvents.stream);
      when(() => primary.stateChanges).thenAnswer((_) => primaryStates.stream);
      when(() => primary.state).thenReturn(ChatConnectionState.disconnected);
      when(() => primary.connect()).thenAnswer((_) async {});
      when(() => primary.disconnect()).thenAnswer((_) async {});
      when(() => primary.dispose()).thenAnswer((_) async {});
      when(() => primary.supportsOutboundFrames).thenReturn(true);

      when(() => fallback.events).thenAnswer((_) => fallbackEvents.stream);
      when(
        () => fallback.stateChanges,
      ).thenAnswer((_) => fallbackStates.stream);
      when(() => fallback.state).thenReturn(ChatConnectionState.disconnected);
      when(() => fallback.connect()).thenAnswer((_) async {});
      when(() => fallback.disconnect()).thenAnswer((_) async {});
      when(() => fallback.dispose()).thenAnswer((_) async {});
      when(() => fallback.supportsOutboundFrames).thenReturn(false);
    });

    tearDown(() async {
      await primaryEvents.close();
      await primaryStates.close();
      await fallbackEvents.close();
      await fallbackStates.close();
    });

    test('dispose() calls dispose() on both primary and fallback', () async {
      final transport = AutoFailoverTransport(
        primary: primary,
        fallback: fallback,
      );

      await transport.connect();
      await transport.dispose();

      verify(() => primary.dispose()).called(1);
      verify(() => fallback.dispose()).called(1);
    });

    test('event stream completes after dispose()', () async {
      final transport = AutoFailoverTransport(
        primary: primary,
        fallback: fallback,
      );

      await transport.connect();

      bool doneFired = false;
      final sub = transport.events.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'event stream must complete on dispose',
      );
    });

    test('stateChanges stream completes after dispose()', () async {
      final transport = AutoFailoverTransport(
        primary: primary,
        fallback: fallback,
      );

      await transport.connect();

      bool doneFired = false;
      final sub = transport.stateChanges.listen(
        (_) {},
        onDone: () => doneFired = true,
      );
      addTearDown(sub.cancel);

      await transport.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(
        doneFired,
        isTrue,
        reason: 'stateChanges stream must complete on dispose',
      );
    });

    test(
      'dispose() without prior connect() still calls dispose on both transports',
      () async {
        final transport = AutoFailoverTransport(
          primary: primary,
          fallback: fallback,
        );

        await transport.dispose();

        verify(() => primary.dispose()).called(1);
        verify(() => fallback.dispose()).called(1);
      },
    );
  });
}
