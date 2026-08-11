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

/// A store that refuses the wipe `ChatClient.logout` ends with, so the
/// teardown has to survive it without losing the queue clear that ran
/// before it.
class _ThrowingClearStore extends MemoryChatLocalDatasource {
  @override
  Future<ChatResult<void>> clear() async => throw StateError('box closed');

  // `MemoryChatLocalDatasource.dispose` clears too; leave the teardown out
  // of the blast radius so only the logout path sees the throw.
  @override
  Future<void> dispose() async {}
}

/// Guards the account boundary of `ChatUiAdapter.signOut()`.
///
/// An attachment whose upload failed on a connectivity error is parked in
/// the client's offline queue (`ChatMessagesController.sendAttachment` →
/// `client.enqueueOfflineAttachment`) and replayed on the next
/// `ConnectedEvent`. The queue carries no owner, so a copy that outlives
/// the logout is uploaded and posted as whoever signs in next — these
/// tests pin that it does not outlive it, and that the cheaper teardown
/// (`disconnect`) still keeps it.
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
  late NomaChatClient client;
  late ChatUiAdapter adapter;

  const me = ChatUser(id: 'u1', displayName: 'Me');
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
  var uploadAttempts = 0;

  ChatConfig configFor(ChatLocalDatasource datasource) => ChatConfig(
    baseUrl: 'http://h/v1',
    realtimeUrl: 'http://h',
    tokenProvider: () async => 't',
    localDatasource: datasource,
    cacheConfig: const CacheConfig(),
  );

  /// Fails the first upload with a network error — the branch that queues —
  /// and lets every later one land, so a replay after the teardown is
  /// visible as a second call.
  void stubUploadFailingOnce() {
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
      if (uploadAttempts == 1) throw const ChatNetworkException('offline');
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
        'metadata': {'clientMessageId': data['clientMessageId']},
      };
    });
  }

  Future<void> bootAdapter(ChatLocalDatasource datasource) async {
    client = NomaChatClient(
      config: configFor(datasource),
      restClient: rest,
      transportManager: transport,
    );
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    await client.connect();
  }

  /// Drives the real failure branch so the queue is populated the way a
  /// user's failed photo populates it, not by calling the queue directly.
  Future<void> queueOneFailedAttachment() async {
    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
      fileName: 'photo.png',
    );
    expect(result.isFailure, isTrue);
    expect(client.pendingOperationCount, 1);
  }

  setUp(() {
    uploadAttempts = 0;
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
    when(() => rest.cancelPending(any())).thenReturn(null);

    stubUploadFailingOnce();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
    await events.close();
    await states.close();
  });

  test(
    'signOut empties the offline queue the signed-out account filled',
    () async {
      await bootAdapter(store);
      await queueOneFailedAttachment();
      expect((await store.getOfflineQueue()).dataOrNull, hasLength(1));

      await adapter.signOut();

      // In-memory, not just persisted: the cache clear `signOut` already did
      // wipes the stored copy, and a queue that only lost that copy would
      // re-persist itself on the next enqueue and drain all the same.
      expect(client.pendingOperationCount, 0);
      expect((await store.getOfflineQueue()).dataOrNull ?? const [], isEmpty);
    },
  );

  test(
    'an attachment queued before signOut never uploads under the next session',
    () async {
      await bootAdapter(store);
      await queueOneFailedAttachment();

      await adapter.signOut();

      // The next account signs in on the same instance — the shape
      // `signOut` documents as supported — and its connection is what
      // drains the queue.
      await adapter.connect();
      events.add(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(uploadAttempts, 1);
      verifyNever(
        () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
      );
    },
  );

  test(
    'a cache datasource that throws on clear still loses the queue',
    () async {
      final throwing = _ThrowingClearStore();
      await bootAdapter(throwing);
      await queueOneFailedAttachment();

      await expectLater(adapter.signOut(), completes);

      expect(client.pendingOperationCount, 0);
    },
  );

  test('disconnect keeps the queue — it is the resumable teardown', () async {
    await bootAdapter(store);
    await queueOneFailedAttachment();

    await adapter.disconnect();

    expect(client.pendingOperationCount, 1);

    // And it still replays for the account that queued it once the
    // connection comes back.
    await adapter.connect();
    events.add(const ConnectedEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(uploadAttempts, 2);
    expect(client.pendingOperationCount, 0);
  });
}
