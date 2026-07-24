import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

/// Covers the real call site in `ChatMessagesController.sendAttachment`
/// (messages_controller.dart) that hands a failed upload to
/// `client.enqueueOfflineAttachment`. Unlike
/// `noma_chat_client_offline_attachment_test.dart` — which calls
/// `enqueueOfflineAttachment` directly and never touches the adapter —
/// this test drives the failure through the public
/// `ChatUiAdapter.messages.sendAttachment` path exactly like the real
/// upload-failure branch, so it fails if that call site is ever removed
/// or short-circuited.
void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(Uint8List(0));
  });

  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;
  late ChatConfig config;
  late NomaChatClient client;
  late ChatUiAdapter adapter;

  const me = ChatUser(id: 'u1', displayName: 'Me');
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

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
    await adapter.dispose();
    await client.dispose();
    await events.close();
    await states.close();
  });

  test(
    'a network failure during sendAttachment enqueues offline and the '
    'queued attachment replays on reconnect, confirming the bubble',
    () async {
      var uploadAttempts = 0;
      when(
        () => rest.uploadBinary(
          any(),
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async {
        uploadAttempts++;
        if (uploadAttempts == 1) {
          throw const ChatNetworkException('offline');
        }
        return {'attachmentId': 'att-1', 'url': 'https://cdn/att-1'};
      });
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer((
        invocation,
      ) async {
        final data = invocation.namedArguments[#data] as Map<String, dynamic>;
        return {
          'id': 'm1',
          'from': 'u1',
          'timestamp': '2025-01-01T00:00:00Z',
          'messageType': 'attachment',
          'attachmentUrl': 'https://cdn/att-1',
          'attachmentId': 'att-1',
          // Echo the idempotency key back inside metadata (the OpenAPI
          // contract) so `MessageMapper.stampIfProvisional` treats this as
          // a non-provisional ack — otherwise the bubble stays pending
          // instead of resolving to the confirmed message below.
          'metadata': {'clientMessageId': data['clientMessageId']},
        };
      });

      client = NomaChatClient(
        config: config,
        restClient: rest,
        transportManager: transport,
      );
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
      await client.connect();

      final controller = adapter.getChatController('r1');

      final result = await adapter.messages.sendAttachment(
        'r1',
        bytes: bytes,
        mimeType: 'image/png',
        fileName: 'photo.png',
      );

      expect(result.isFailure, isTrue);
      expect(controller.messages, hasLength(1));
      final tempId = controller.messages.single.id;
      expect(controller.isFailed(tempId), isTrue);

      // The real assertion for C5: if the `enqueueOfflineAttachment` call
      // in `ChatMessagesController.sendAttachment`'s failure branch is
      // removed, nothing lands in the persisted offline queue and this
      // fails.
      final queuedBeforeDrain =
          (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queuedBeforeDrain, hasLength(1));
      expect(queuedBeforeDrain.single['type'], 'sendAttachment');
      expect(queuedBeforeDrain.single['roomId'], 'r1');
      expect(queuedBeforeDrain.single['mimeType'], 'image/png');

      events.add(const ConnectedEvent());
      events.add(const DisconnectedEvent());
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(
                () => rest.uploadBinary(
                  '/attachments',
                  captureAny(),
                  'image/png',
                  onProgress: any(named: 'onProgress'),
                ),
              ).captured.last
              as Uint8List;
      expect(captured, bytes);

      expect(controller.isFailed(tempId), isFalse);
      final confirmed = controller.messages.singleWhere((m) => m.id == 'm1');
      expect(confirmed.attachmentId, 'att-1');

      final queuedAfterDrain =
          (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queuedAfterDrain, isEmpty);
    },
  );
}
