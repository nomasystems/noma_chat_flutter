import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}

/// Covers R2-16: an attachment upload that fails while offline must enter
/// the offline retry queue (via [NomaChatClient.enqueueOfflineAttachment])
/// and be replayed — bytes intact — on the next successful drain, with
/// [NomaChatClient.onOfflineMessageSent] reconciling the temp id exactly
/// like a queued text send.
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
    await events.close();
    await states.close();
  });

  NomaChatClient build() => NomaChatClient(
    config: config,
    restClient: rest,
    transportManager: transport,
  );

  test(
    'a NetworkFailure during upload queues the attachment and replays it '
    'on reconnect, preserving bytes and reconciling via '
    'onOfflineMessageSent (R2-16)',
    () async {
      when(
        () => rest.uploadBinary(
          any(),
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) async => {'attachmentId': 'att-1', 'url': 'https://cdn/att-1'},
      );
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 'm1',
          'from': 'u1',
          'timestamp': '2025-01-01T00:00:00Z',
          'messageType': 'attachment',
          'attachmentUrl': 'https://cdn/att-1',
          'attachmentId': 'att-1',
        },
      );

      final client = build();
      String? reconciledRoomId;
      String? reconciledTempId;
      ChatMessage? reconciledMessage;
      client.onOfflineMessageSent = (roomId, tempId, message) {
        reconciledRoomId = roomId;
        reconciledTempId = tempId;
        reconciledMessage = message;
      };
      await client.connect();

      // The upload has already failed by the time this is called — mirrors
      // `ChatMessagesController.sendAttachment`'s upload-failure branch.
      client.enqueueOfflineAttachment(
        roomId: 'r1',
        bytes: bytes,
        mimeType: 'image/png',
        causeFailure: const NetworkFailure(),
        fileName: 'photo.png',
        tempId: 'temp-1',
        clientMessageId: 'temp-1',
      );

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
              ).captured.single
              as Uint8List;
      expect(captured, bytes);

      expect(reconciledRoomId, 'r1');
      expect(reconciledTempId, 'temp-1');
      expect(reconciledMessage?.attachmentId, 'att-1');

      final queuedAfterDrain =
          (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queuedAfterDrain, isEmpty);
    },
  );

  test(
    'a permanent failure (ValidationFailure) during upload is NOT queued '
    '— there is nothing durable to retry (R2-16 gate)',
    () async {
      final client = build();
      await client.connect();

      client.enqueueOfflineAttachment(
        roomId: 'r1',
        bytes: bytes,
        mimeType: 'image/png',
        causeFailure: const ValidationFailure(message: 'file too large'),
        tempId: 'temp-2',
        clientMessageId: 'temp-2',
      );

      final queued = (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queued, isEmpty);
    },
  );

  test(
    'an attachment over offlineQueueMaxAttachmentBytes is NOT queued and '
    'reports attachment_too_large via onOperationDropped instead of '
    'discarding silently (C1)',
    () async {
      config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: store,
        cacheConfig: const CacheConfig(offlineQueueMaxAttachmentBytes: 3),
      );
      final client = build();
      await client.connect();

      PendingOperation? droppedOp;
      String? droppedReason;
      client.onOperationDropped = (op, reason) {
        droppedOp = op;
        droppedReason = reason;
      };

      client.enqueueOfflineAttachment(
        roomId: 'r1',
        bytes: bytes, // 5 bytes > the 3-byte cap configured above.
        mimeType: 'image/png',
        causeFailure: const NetworkFailure(),
        tempId: 'temp-3',
        clientMessageId: 'temp-3',
      );

      expect(droppedReason, 'attachment_too_large');
      expect(droppedOp, isA<PendingSendAttachment>());
      expect((droppedOp as PendingSendAttachment).roomId, 'r1');

      final queued = (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queued, isEmpty);
    },
  );

  test(
    'an attachment at or under offlineQueueMaxAttachmentBytes is queued '
    'normally (C1 boundary)',
    () async {
      config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: store,
        cacheConfig: CacheConfig(offlineQueueMaxAttachmentBytes: bytes.length),
      );
      final client = build();
      await client.connect();

      client.enqueueOfflineAttachment(
        roomId: 'r1',
        bytes: bytes,
        mimeType: 'image/png',
        causeFailure: const NetworkFailure(),
        tempId: 'temp-4',
        clientMessageId: 'temp-4',
      );

      final queued = (await store.getOfflineQueue()).dataOrNull ?? const [];
      expect(queued, hasLength(1));
    },
  );

  test(
    'without an offline queue configured, enqueueOfflineAttachment is a '
    'no-op instead of throwing',
    () async {
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

      expect(
        () => client.enqueueOfflineAttachment(
          roomId: 'r1',
          bytes: bytes,
          mimeType: 'image/png',
          causeFailure: const NetworkFailure(),
        ),
        returnsNormally,
      );
    },
  );
}
