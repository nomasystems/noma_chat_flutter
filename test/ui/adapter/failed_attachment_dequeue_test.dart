import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

/// What "Discard" and "Retry" mean for a photo whose upload died on the
/// network — the one failure that also puts the file in the offline queue.
///
/// The queue drains on every connect, so the bubble is only half the row:
/// a discard that leaves the queued copy behind sends the photo the user
/// just took back, and a retry that leaves it behind sends the photo twice
/// under two idempotency keys the server cannot relate. Both land in a
/// room other people are reading, and neither can be undone.
///
/// The failure is deliberately a [ChatNetworkException] — unlike
/// `failed_attachment_retry_test.dart`, which raises to get an
/// `UnexpectedFailure` the queue refuses, so it can measure the manual
/// path with nothing replaying behind it. Here the replay IS the subject.
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
  late List<String> postedPaths;
  late int uploadAttempts;
  late bool uploadsFail;

  const me = ChatUser(id: 'u1', displayName: 'Me');
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

  Future<List<Map<String, dynamic>>> queuedOps() async =>
      (await store.getOfflineQueue()).dataOrNull ?? const [];

  setUp(() {
    transport = _MockTransport();
    rest = _MockRest();
    store = MemoryChatLocalDatasource();
    events = StreamController<ChatEvent>.broadcast();
    states = StreamController<ChatConnectionState>.broadcast();
    postedPaths = [];
    uploadAttempts = 0;
    uploadsFail = true;

    when(() => transport.events).thenAnswer((_) => events.stream);
    when(() => transport.stateChanges).thenAnswer((_) => states.stream);
    when(() => transport.state).thenReturn(ChatConnectionState.disconnected);
    when(() => transport.isWsConnected).thenReturn(false);
    when(() => transport.connect()).thenAnswer((_) async {});
    when(() => transport.disconnect()).thenAnswer((_) async {});
    when(() => transport.dispose()).thenAnswer((_) async {});
    when(() => transport.notifyTokenRotated()).thenAnswer((_) async {});
    when(() => rest.userId).thenReturn('u1');

    when(
      () => rest.uploadBinary(
        any(),
        any(),
        any(),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      uploadAttempts++;
      if (uploadsFail) throw const ChatNetworkException('offline');
      return {'attachmentId': 'att-1', 'url': 'https://cdn/att-1'};
    });
    when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer((
      invocation,
    ) async {
      postedPaths.add(invocation.positionalArguments.first as String);
      final data = invocation.namedArguments[#data] as Map<String, dynamic>;
      return {
        'id': 'm${postedPaths.length}',
        'from': 'u1',
        'timestamp': '2025-01-01T00:00:00Z',
        'messageType': 'attachment',
        'attachmentUrl': 'https://cdn/att-1',
        'attachmentId': 'att-1',
        'metadata': {'clientMessageId': data['clientMessageId']},
      };
    });

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

  /// Sends a photo that fails on the network, returning the failed row's
  /// id. The offline queue holds the whole upload+send at this point.
  Future<String> sendQueuedPhoto() async {
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
    final tempId = controller.messages.single.id;
    expect(controller.isFailed(tempId), isTrue);
    expect(await queuedOps(), hasLength(1));
    return tempId;
  }

  /// A reconnect, which is what drains the queue in the field.
  Future<void> reconnect() async {
    events.add(const ConnectedEvent());
    events.add(const DisconnectedEvent());
    events.add(const ConnectedEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('discarding a failed photo takes it out of the offline queue, so the '
      'next drain sends nothing', () async {
    final tempId = await sendQueuedPhoto();
    final controller = adapter.getChatController('r1');

    final discarded = await adapter.messages.discardFailed('r1', tempId);
    await Future<void>.delayed(Duration.zero);
    expect(discarded.isSuccess, isTrue);

    // The entry is gone from the persisted queue, not merely from the view.
    expect(await queuedOps(), isEmpty);
    expect(client.pendingOperationCount, 0);

    // The transport comes back and the queue drains: before the fix this
    // re-uploaded the photo and posted it into the room the user had just
    // cancelled it from.
    uploadsFail = false;
    await reconnect();

    expect(uploadAttempts, 1);
    expect(postedPaths, isEmpty);
    expect(controller.messages, isEmpty);
  });

  test('retrying a failed photo sends it once: the queued copy does not land '
      'as a second message', () async {
    final tempId = await sendQueuedPhoto();
    final controller = adapter.getChatController('r1');

    uploadsFail = false;
    final retried = await adapter.messages.retrySend('r1', tempId);
    await Future<void>.delayed(Duration.zero);

    expect(retried.isSuccess, isTrue);
    expect(postedPaths, ['/rooms/r1/messages']);
    // The retry re-drives the send under a fresh id, so the entry the
    // original failure queued is stale — leaving it would put the same
    // photo in the room a second time on the next reconnect.
    expect(await queuedOps(), isEmpty);
    expect(client.pendingOperationCount, 0);

    await reconnect();

    expect(uploadAttempts, 2);
    expect(postedPaths, hasLength(1));
    expect(controller.failedMessageIds, isEmpty);
    expect(controller.messages.map((m) => m.id), ['m1']);
  });
}

class _MockTransport extends Mock implements TransportManager {}

class _MockRest extends Mock implements RestClient {}
