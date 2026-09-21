import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

class _ThrowingSaveOfflineQueueDatasource extends MemoryChatLocalDatasource {
  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) async => throw StateError('disk full (simulated)');
}

/// Pins the fix for a real production bug: `NomaChatClient` built its
/// `CacheManager` and `OfflineQueue` without forwarding `ChatConfig.logs`,
/// so every `logs.cache(...)` call the cache layer makes was silently a
/// no-op in any app that only wired `ChatConfig.logSink`/`logLevel` (the
/// structured pipeline) rather than the legacy `logger` callback.
void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  late _MockTransport transport;
  late _MockRest rest;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;

  setUp(() {
    transport = _MockTransport();
    rest = _MockRest();
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

  test(
    'a persist failure in the offline queue built by NomaChatClient logs '
    'through ChatConfig.logs (config.logSink), not just the legacy logger',
    () async {
      final buffer = BufferChatLogSink();
      final config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: _ThrowingSaveOfflineQueueDatasource(),
        cacheConfig: const CacheConfig(),
        logSink: buffer,
        logLevel: ChatLogLevel.warn,
      );
      final client = NomaChatClient(
        config: config,
        restClient: rest,
        transportManager: transport,
      );
      addTearDown(client.dispose);

      client.enqueueOfflineAttachment(
        roomId: 'r1',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        causeFailure: const NetworkFailure(),
        tempId: 'temp-1',
        clientMessageId: 'temp-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        buffer.records.any(
          (r) =>
              r.tag == ChatLogTag.cache &&
              r.level == ChatLogLevel.warn &&
              r.message.contains('persist failed'),
        ),
        isTrue,
      );
    },
  );

  test('restoring cache timestamps through NomaChatClient logs a cache debug '
      'record via ChatConfig.logs (config.logSink)', () async {
    final buffer = BufferChatLogSink();
    final config = ChatConfig(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
      localDatasource: MemoryChatLocalDatasource(),
      cacheConfig: const CacheConfig(),
      logSink: buffer,
      logLevel: ChatLogLevel.debug,
    );
    final client = NomaChatClient(
      config: config,
      restClient: rest,
      transportManager: transport,
    );
    addTearDown(client.dispose);

    await client.restoreCacheTimestamps();

    expect(
      buffer.records.any(
        (r) =>
            r.tag == ChatLogTag.cache &&
            r.level == ChatLogLevel.debug &&
            r.message.contains('restored TTL timestamps'),
      ),
      isTrue,
    );
  });
}
