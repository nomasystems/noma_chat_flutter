import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

/// Regression coverage for F3: the offline queue used to only drain on a
/// RECONNECT (`_hasConnectedOnce` guard), so a message queued while the app
/// had never yet connected sat unsent until the connection dropped and came
/// back. Catch-up must stay reconnect-only — there is nothing to catch up on
/// a session that never disconnected.
void main() {
  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;

  setUp(() {
    transport = _MockTransport();
    rest = _MockRest();
    store = MemoryChatLocalDatasource();
    events = StreamController<ChatEvent>.broadcast();
    states = StreamController<ChatConnectionState>.broadcast();

    when(() => transport.events).thenAnswer((_) => events.stream);
    when(() => transport.stateChanges).thenAnswer((_) => states.stream);
    when(() => transport.state).thenReturn(ChatConnectionState.disconnected);
    when(() => transport.isWsConnected).thenReturn(false);
    when(() => transport.connect()).thenAnswer((_) async {});
    when(() => transport.disconnect()).thenAnswer((_) async {});
    when(() => transport.dispose()).thenAnswer((_) async {});
    when(() => rest.userId).thenReturn('u1');
  });

  tearDown(() async {
    await events.close();
    await states.close();
  });

  NomaChatClient buildWithCache({bool enableCatchUp = false}) => NomaChatClient(
    config: ChatConfig(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
      localDatasource: store,
      cacheConfig: const CacheConfig(),
      enableReconnectCatchUp: enableCatchUp,
    ),
    restClient: rest,
    transportManager: transport,
  );

  test(
    'a queued sendMessage is sent on the very first ConnectedEvent, '
    'without waiting for a reconnect',
    () async {
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 'm-server',
          'from': 'u1',
          'timestamp': '2025-01-01T00:00:00Z',
          'text': 'hi',
          'messageType': 'regular',
        },
      );

      await store.saveOfflineQueue([
        {
          'id': 'op-cold-start',
          'type': 'sendMessage',
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
          'roomId': 'r1',
          'text': 'hi',
          'messageType': 'regular',
          'clientMessageId': 'cmid-cold-start',
        },
      ]);

      final client = buildWithCache();

      await client.connect();
      // connect() restores the persisted queue before subscribing to
      // events.
      expect(client.pendingOperationCount, 1);
      // First-ever ConnectedEvent for this session — no DisconnectedEvent
      // preceded it.
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final queued = (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(
        queued,
        isEmpty,
        reason:
            'the offline queue must drain on the first connection of a '
            'cold start, not only after a subsequent reconnect',
      );
      expect(client.pendingOperationCount, 0);
      verify(() => rest.post(any(), data: any(named: 'data'))).called(1);
    },
  );

  test(
    'catch-up does NOT fire on the first ConnectedEvent (nothing to catch '
    'up on a session that never disconnected)',
    () async {
      when(() => rest.get(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {'rooms': []});

      final client = buildWithCache(enableCatchUp: true);
      await client.connect();
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      );
    },
  );

  test(
    'catch-up fires after a real disconnect/reconnect cycle',
    () async {
      when(() => rest.get(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {'rooms': []});

      final client = buildWithCache(enableCatchUp: true);
      await client.connect();
      events.add(const ConnectedEvent());
      events.add(const DisconnectedEvent());
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).called(1);
    },
  );

  test(
    'flushPendingOperations drains the queue on demand, without a '
    'ConnectedEvent',
    () async {
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 'm-server',
          'from': 'u1',
          'timestamp': '2025-01-01T00:00:00Z',
          'text': 'hi',
          'messageType': 'regular',
        },
      );

      await store.saveOfflineQueue([
        {
          'id': 'op-manual-flush',
          'type': 'sendMessage',
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
          'roomId': 'r1',
          'text': 'hi',
          'messageType': 'regular',
          'clientMessageId': 'cmid-manual-flush',
        },
      ]);

      final client = buildWithCache();
      await client.connect();
      expect(client.pendingOperationCount, 1);

      await client.flushPendingOperations();

      expect(client.pendingOperationCount, 0);
      verify(() => rest.post(any(), data: any(named: 'data'))).called(1);
    },
  );

  test(
    'pendingOperationCount and flushPendingOperations are no-ops without '
    'an offline queue configured',
    () async {
      final client = NomaChatClient(
        config: ChatConfig(
          baseUrl: 'http://h/v1',
          realtimeUrl: 'http://h',
          tokenProvider: () async => 't',
        ),
        restClient: rest,
        transportManager: transport,
      );

      expect(client.pendingOperationCount, 0);
      await client.flushPendingOperations();
    },
  );
}
