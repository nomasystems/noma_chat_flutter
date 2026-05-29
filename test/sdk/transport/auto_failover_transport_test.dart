import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
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
  });
}
