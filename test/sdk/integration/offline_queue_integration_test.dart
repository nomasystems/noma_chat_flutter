import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

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

  Future<void> reconnectCycle() async {
    events.add(const ConnectedEvent());
    events.add(const DisconnectedEvent());
    events.add(const ConnectedEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('a send that fails with NetworkFailure is enqueued and replayed as a '
      'REST POST on reconnect', () async {
    var attempt = 0;
    when(
      () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
    ).thenAnswer((_) async {
      attempt++;
      if (attempt == 1) throw const ChatNetworkException();
      return {
        'id': 'm-server',
        'from': 'u1',
        'timestamp': '2025-01-01T00:00:00Z',
        'text': 'offline hi',
        'messageType': 'regular',
      };
    });

    final client = build();
    await client.connect();

    final firstSend = await client.messages.send(
      'r1',
      text: 'offline hi',
      tempId: 'tmp-1',
      clientMessageId: 'cmid-1',
    );
    expect(firstSend.isFailure, isTrue);
    expect(firstSend.failureOrNull, isA<NetworkFailure>());

    await reconnectCycle();

    verify(
      () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
    ).called(2);
    expect((await store.getOfflineQueue()).dataOrNull, isEmpty);
  });

  test('onOfflineMessageSent fires with the server message once the queued '
      'send is replayed', () async {
    var attempt = 0;
    when(
      () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
    ).thenAnswer((_) async {
      attempt++;
      if (attempt == 1) throw const ChatNetworkException();
      return {
        'id': 'm-server',
        'from': 'u1',
        'timestamp': '2025-01-01T00:00:00Z',
        'text': 'recovered',
        'messageType': 'regular',
      };
    });

    final client = build();
    String? sentRoomId;
    String? sentTempId;
    ChatMessage? sentMessage;
    client.onOfflineMessageSent = (roomId, tempId, message) {
      sentRoomId = roomId;
      sentTempId = tempId;
      sentMessage = message;
    };
    await client.connect();

    await client.messages.send('r1', text: 'recovered', tempId: 'tmp-9');
    await reconnectCycle();

    expect(sentRoomId, 'r1');
    expect(sentTempId, 'tmp-9');
    expect(sentMessage?.id, 'm-server');
  });

  test('a delete that fails with NetworkFailure is replayed as a REST DELETE '
      'on reconnect', () async {
    var attempt = 0;
    when(() => rest.delete('/rooms/r1/messages/m1')).thenAnswer((_) async {
      attempt++;
      if (attempt == 1) throw const ChatNetworkException();
    });

    final client = build();
    await client.connect();

    final firstDelete = await client.messages.delete('r1', 'm1');
    expect(firstDelete.isFailure, isTrue);
    expect(firstDelete.failureOrNull, isA<NetworkFailure>());

    await reconnectCycle();

    verify(() => rest.delete('/rooms/r1/messages/m1')).called(2);
    expect((await store.getOfflineQueue()).dataOrNull, isEmpty);
  });

  test('a server failure on send is surfaced without enqueueing', () async {
    when(
      () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
    ).thenThrow(const ChatApiException(statusCode: 500, message: 'boom'));

    final client = build();
    await client.connect();

    final result = await client.messages.send('r1', text: 'nope');
    expect(result.failureOrNull, isA<ServerFailure>());

    await reconnectCycle();

    verify(
      () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
    ).called(1);
    expect((await store.getOfflineQueue()).dataOrNull ?? const [], isEmpty);
  });
}
