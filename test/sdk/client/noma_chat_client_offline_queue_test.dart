import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

/// Drives `_processOfflineQueue` for each `PendingOperation` subtype.
/// We seed the in-memory datasource with pending entries, then trigger a
/// reconnect cycle so the client drains the queue.
void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;
  late ChatConfig config;

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
    when(() => transport.notifyTokenRotated()).thenAnswer((_) async {});
    when(() => rest.userId).thenReturn('u1');

    config = ChatConfig(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
      localDatasource: store,
      cacheConfig: const CacheConfig(),
    );
  });

  tearDown(() async {
    await events.close();
    await states.close();
  });

  NomaChatClient build() => NomaChatClient(
    config: config,
    restClient: rest,
    transportManager: transport,
  );

  test('logout clears the local cache + offline queue', () async {
    await store.saveOfflineQueue([
      {
        'id': 'op-x',
        'type': 'deleteMessage',
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
        'roomId': 'r1',
        'messageId': 'm1',
      },
    ]);
    final client = build();
    await client.connect();

    await client.logout();

    expect((await store.getOfflineQueue()).dataOrNull, isEmpty);
  });

  test('restore() picks up persisted operations before connecting', () async {
    // Pre-seed a serialised pending op.
    await store.saveOfflineQueue([
      {
        'id': 'op-1',
        'type': 'deleteMessage',
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
        'roomId': 'r1',
        'messageId': 'm1',
      },
    ]);

    // Instantiating the client doesn't restore by itself; calling connect()
    // does (it invokes _offlineQueue.restore() internally before listening
    // to events). We just verify the path runs without throwing.
    final client = build();
    await client.connect();
    verify(() => transport.connect()).called(1);
  });

  test('configuring without a cache disables the offline queue path', () async {
    final noCacheConfig = ChatConfig(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
    );
    final client = NomaChatClient(
      config: noCacheConfig,
      restClient: rest,
      transportManager: transport,
    );
    await client.connect();
    await client.logout();
  });

  test('reconnect cycle with empty queue does nothing problematic', () async {
    final client = build();
    await client.connect();
    events.add(const ConnectedEvent());
    events.add(const DisconnectedEvent());
    events.add(const ConnectedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(client.lastDisconnectedAt, isNull);
  });

  test(
    'onOfflineMessageSent callback is invocable (no-op when queue empty)',
    () async {
      var called = false;
      final client = build();
      client.onOfflineMessageSent = (_, __, ___) => called = true;
      await client.connect();
      events.add(const ConnectedEvent());
      events.add(const DisconnectedEvent());
      events.add(const ConnectedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(called, false); // queue was empty
    },
  );

  group('offline queue payload coverage (serialised PendingOperation)', () {
    Future<void> seedAndDrain(Map<String, dynamic> op) async {
      await store.saveOfflineQueue([
        {
          'id': 'op',
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
          ...op,
        },
      ]);
      final client = build();
      await client.connect();
      events.add(const ConnectedEvent());
      events.add(const DisconnectedEvent());
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    Future<bool> queueIsDrained() async =>
        ((await store.getOfflineQueue()).dataOrNull ?? const []).isEmpty;

    test('deleteMessage drains a DELETE on the message path', () async {
      when(() => rest.delete('/rooms/r1/messages/m1')).thenAnswer((_) async {});

      await seedAndDrain({
        'type': 'deleteMessage',
        'roomId': 'r1',
        'messageId': 'm1',
      });

      verify(() => rest.delete('/rooms/r1/messages/m1')).called(1);
      expect(await queueIsDrained(), isTrue);
    });

    test('editMessage drains a PUT carrying the edited text', () async {
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      await seedAndDrain({
        'type': 'editMessage',
        'roomId': 'r1',
        'messageId': 'm1',
        'text': 'edited',
      });

      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/messages/m1',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['text'], 'edited');
      expect(await queueIsDrained(), isTrue);
    });

    test('deleteReaction drains a DELETE on the reactions path', () async {
      when(
        () => rest.delete('/rooms/r1/messages/m1/reactions'),
      ).thenAnswer((_) async {});

      await seedAndDrain({
        'type': 'deleteReaction',
        'roomId': 'r1',
        'messageId': 'm1',
      });

      verify(() => rest.delete('/rooms/r1/messages/m1/reactions')).called(1);
      expect(await queueIsDrained(), isTrue);
    });

    test(
      'createRoom drains a POST to /rooms with audience + members',
      () async {
        when(
          () => rest.post('/rooms', data: any(named: 'data')),
        ).thenAnswer((_) async => {'roomId': 'room-new', 'audience': 'public'});

        await seedAndDrain({
          'type': 'createRoom',
          'name': 'R',
          'audience': 'public',
          'members': <String>['u2'],
        });

        final captured =
            verify(
                  () => rest.post('/rooms', data: captureAny(named: 'data')),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['audience'], 'public');
        expect(captured['name'], 'R');
        expect(captured['members'], ['u2']);
        expect(await queueIsDrained(), isTrue);
      },
    );

    test(
      'updateRoomConfig drains a PUT to /config with the new name',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        await seedAndDrain({
          'type': 'updateRoomConfig',
          'roomId': 'r1',
          'name': 'New',
        });

        final captured =
            verify(
                  () => rest.putVoid(
                    '/rooms/r1/config',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['name'], 'New');
        expect(await queueIsDrained(), isTrue);
      },
    );

    test('addMember drains a POST to /users with the userId', () async {
      when(
        () => rest.postRaw('/rooms/r1/users', data: any(named: 'data')),
      ).thenAnswer((_) async => null);

      await seedAndDrain({
        'type': 'addMember',
        'roomId': 'r1',
        'userId': 'u2',
        'role': 'admin',
      });

      final captured =
          verify(
                () => rest.postRaw(
                  '/rooms/r1/users',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['userIds'], ['u2']);
      expect(await queueIsDrained(), isTrue);
    });

    test('removeMember drains a DELETE on the user path', () async {
      when(() => rest.delete('/rooms/r1/users/u2')).thenAnswer((_) async {});

      await seedAndDrain({
        'type': 'removeMember',
        'roomId': 'r1',
        'userId': 'u2',
      });

      verify(() => rest.delete('/rooms/r1/users/u2')).called(1);
      expect(await queueIsDrained(), isTrue);
    });
  });
}
