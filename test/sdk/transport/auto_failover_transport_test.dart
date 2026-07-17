import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/transport/auto_failover_transport.dart';
import 'package:noma_chat/src/_internal/transport/realtime_transport.dart';

class _MockTransport extends Mock implements RealtimeTransport {}

void main() {
  group('AutoFailoverTransport', () {
    late _MockTransport primary;
    late _MockTransport fallback;
    late StreamController<ChatEvent> primaryEvents;
    late StreamController<ChatConnectionState> primaryStates;
    late StreamController<ChatEvent> fallbackEvents;
    late StreamController<ChatConnectionState> fallbackStates;
    late AutoFailoverTransport transport;

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
      when(() => primary.authTerminated).thenReturn(false);
      when(() => fallback.authTerminated).thenReturn(false);
      when(() => primary.transportDisabled).thenReturn(false);
      when(() => fallback.transportDisabled).thenReturn(false);
      when(() => primary.connect()).thenAnswer((_) async {});
      when(() => primary.disconnect()).thenAnswer((_) async {});
      when(() => primary.supportsOutboundFrames).thenReturn(true);

      when(() => fallback.events).thenAnswer((_) => fallbackEvents.stream);
      when(
        () => fallback.stateChanges,
      ).thenAnswer((_) => fallbackStates.stream);
      when(() => fallback.state).thenReturn(ChatConnectionState.disconnected);
      when(() => fallback.connect()).thenAnswer((_) async {});
      when(() => fallback.disconnect()).thenAnswer((_) async {});
      when(() => fallback.supportsOutboundFrames).thenReturn(false);
      when(() => primary.dispose()).thenAnswer((_) async {});
      when(() => fallback.dispose()).thenAnswer((_) async {});

      transport = AutoFailoverTransport(primary: primary, fallback: fallback);
    });

    tearDown(() async {
      await transport.dispose();
      await primaryEvents.close();
      await primaryStates.close();
      await fallbackEvents.close();
      await fallbackStates.close();
    });

    test('promotes the fallback after repeated initial primary failures even '
        'though the primary never connected once', () async {
      await transport.connect();

      // Primary keeps failing its initial connection — below threshold the
      // fallback stays dormant.
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => fallback.connect());

      // Third consecutive initial failure crosses the threshold (3) and the
      // SSE fallback is promoted, escaping the WS-only reconnect loop.
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);
    });

    test(
      'promotes the fallback immediately when the primary reports '
      'transportDisabled (WS close 4006), even though the primary never '
      'connected once and the initial-failure threshold is not reached',
      () async {
        await transport.connect();

        // The server disabled the WS transport: the primary latches the flag
        // synchronously and suspends its own reconnect loop, so no further
        // error states would ever arrive — waiting for the threshold (3)
        // would strand the session without realtime.
        when(() => primary.transportDisabled).thenReturn(true);
        primaryStates.add(ChatConnectionState.error);
        await Future<void>.delayed(Duration.zero);

        verify(() => fallback.connect()).called(1);
      },
    );

    test('transportDisabled promotion also applies after the primary had '
        'connected: the fallback is armed and the primary is not re-promoted '
        'by the failover itself', () async {
      await transport.connect();
      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      when(() => primary.transportDisabled).thenReturn(true);
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);

      verify(() => fallback.connect()).called(1);
      // The composite absorbs the disabled primary — it does not surface
      // as disabled itself.
      expect(transport.transportDisabled, isFalse);
    });

    test('fallback re-arms on every primary drop after recovery', () async {
      await transport.connect();

      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);

      when(() => primary.state).thenReturn(ChatConnectionState.connected);
      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.disconnect()).called(1);

      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);

      when(() => primary.state).thenReturn(ChatConnectionState.connected);
      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.disconnect()).called(1);

      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);
    });

    test(
      'fallback is not started before the primary has ever connected',
      () async {
        await transport.connect();

        primaryStates.add(ChatConnectionState.disconnected);
        primaryStates.add(ChatConnectionState.error);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => fallback.connect());
      },
    );

    test('a repeated drop without a recovery in between does not re-trigger '
        'a second fallback connect', () async {
      await transport.connect();

      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);

      primaryStates.add(ChatConnectionState.error);
      primaryStates.add(ChatConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => fallback.connect());
    });

    test('fallback connect failure clears the active flag so the next drop '
        'can re-attempt', () async {
      when(
        () => fallback.connect(),
      ).thenAnswer((_) async => throw StateError('boom'));

      await transport.connect();

      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => fallback.connect()).called(1);

      when(() => fallback.connect()).thenAnswer((_) async {});
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);
    });

    test('a terminal auth failure suspends both transports and never promotes '
        'the fallback (no rejected-token reuse)', () async {
      await transport.connect();

      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // WS 4005: the primary emits the terminal error BEFORE the error
      // state. The failover must latch terminal from the event and skip the
      // fallback so the rejected token is never replayed over SSE.
      primaryEvents.add(
        const ChatEvent.error(
          exception: ChatAuthException.terminal('too_many_auth_attempts'),
        ),
      );
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => fallback.connect());
      expect(transport.state, ChatConnectionState.error);
    });

    test(
      'an error STATE delivered before the terminal event still suspends '
      'the fallback (order-independent via the primary terminal flag)',
      () async {
        await transport.connect();
        primaryStates.add(ChatConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        // Worst case the event-only latch could not cover: the WS set its
        // synchronous terminal flag, but the error STATE is delivered before
        // the terminal EVENT. The state handler must consult
        // `primary.authTerminated` and refuse to promote the fallback.
        when(() => primary.authTerminated).thenReturn(true);
        primaryStates.add(ChatConnectionState.error);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => fallback.connect());
        expect(transport.state, ChatConnectionState.error);
      },
    );

    test('the terminal-auth latch clears on a fresh primary connection so '
        'failover resumes after re-auth', () async {
      await transport.connect();

      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      primaryEvents.add(
        const ChatEvent.error(exception: ChatAuthException.terminal()),
      );
      primaryStates.add(ChatConnectionState.error);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => fallback.connect());

      // App re-authenticated and the primary reconnected: a later transient
      // drop promotes the fallback again.
      primaryStates.add(ChatConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      primaryStates.add(ChatConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      verify(() => fallback.connect()).called(1);
    });
  });
}
