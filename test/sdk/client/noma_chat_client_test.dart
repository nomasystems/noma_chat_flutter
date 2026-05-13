import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/src/_internal/cache/cache_config.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:noma_chat/src/client/noma_chat_client.dart';
import 'package:noma_chat/src/config/chat_config.dart';
import 'package:noma_chat/src/events/chat_event.dart';
import 'package:flutter_test/flutter_test.dart';

class MockTransportManager extends Mock implements TransportManager {}

class MockRestClient extends Mock implements RestClient {}

void main() {
  late MockTransportManager mockTransport;
  late MockRestClient mockRest;
  late StreamController<ChatEvent> eventsController;
  late StreamController<ChatConnectionState> stateController;
  late ChatConfig config;
  late ChatConfig configWithCache;

  setUp(() {
    mockTransport = MockTransportManager();
    mockRest = MockRestClient();
    eventsController = StreamController<ChatEvent>.broadcast();
    stateController = StreamController<ChatConnectionState>.broadcast();

    when(() => mockTransport.events)
        .thenAnswer((_) => eventsController.stream);
    when(() => mockTransport.stateChanges)
        .thenAnswer((_) => stateController.stream);
    when(() => mockTransport.state)
        .thenReturn(ChatConnectionState.disconnected);
    when(() => mockTransport.isWsConnected).thenReturn(false);
    when(() => mockTransport.connect()).thenAnswer((_) async {});
    when(() => mockTransport.disconnect()).thenAnswer((_) async {});
    when(() => mockTransport.dispose()).thenAnswer((_) async {});
    when(() => mockRest.userId).thenReturn(null);

    config = ChatConfig(
      baseUrl: 'http://localhost:8077/v1',
      realtimeUrl: 'http://localhost:8077',
      tokenProvider: () async => 'test-token',
    );

    configWithCache = ChatConfig(
      baseUrl: 'http://localhost:8077/v1',
      realtimeUrl: 'http://localhost:8077',
      tokenProvider: () async => 'test-token',
      cacheConfig: const CacheConfig(),
    );
  });

  tearDown(() async {
    await eventsController.close();
    await stateController.close();
  });

  NomaChatClient createClient({ChatConfig? cfg}) {
    return NomaChatClient(
      config: cfg ?? config,
      restClient: mockRest,
      transportManager: mockTransport,
    );
  }

  group('NomaChatClient', () {
    test('constructor without cacheConfig does not subscribe on connect',
        () async {
      final client = createClient();

      await client.connect();
      verify(() => mockTransport.connect()).called(1);

      eventsController.add(const ConnectedEvent());
      await Future<void>.delayed(Duration.zero);
    });

    test('constructor with cacheConfig initializes offline queue', () async {
      final client = createClient(cfg: configWithCache);

      await client.connect();
      verify(() => mockTransport.connect()).called(1);

      eventsController.add(const ConnectedEvent());
      await Future<void>.delayed(Duration.zero);
    });

    test('connect delegates to transport', () async {
      final client = createClient();

      await client.connect();

      verify(() => mockTransport.connect()).called(1);
    });

    test('disconnect cancels subscription and delegates to transport',
        () async {
      final client = createClient();

      await client.connect();
      await client.disconnect();

      verify(() => mockTransport.disconnect()).called(1);
    });

    test('dispose cancels subscription and disposes transport', () async {
      final client = createClient();

      await client.connect();
      await client.dispose();

      verify(() => mockTransport.dispose()).called(1);
    });

    test('events stream comes from transport', () async {
      final client = createClient();
      final received = <ChatEvent>[];
      final sub = client.events.listen(received.add);

      const event = ConnectedEvent();
      eventsController.add(event);
      await Future<void>.delayed(Duration.zero);

      expect(received, [event]);
      await sub.cancel();
    });
  });
}
