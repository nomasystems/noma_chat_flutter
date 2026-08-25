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

/// `403 {"detail":"blocked"}` on a send: the recipient blocks the sender.
///
/// WhatsApp parity — and the product decision behind it — is that the
/// sender learns nothing. The bubble must look like an ordinary send that
/// left the device, and then stay there: one tick, for good. Two halves,
/// both covered here. The rejection is swallowed on EVERY send path, not
/// just the plain one, and the row it leaves behind can never be advanced
/// to ✓✓ by a delivery cursor that was computed from server history the
/// message is not in.
void main() {
  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;
  late NomaChatClient client;
  late ChatUiAdapter adapter;

  const me = ChatUser(id: 'me', displayName: 'Me');

  const blocked = ChatForbiddenException(
    body: {'code': 403, 'detail': 'blocked', 'error': 'blocked'},
    errorToken: 'blocked',
  );

  /// What `POST /rooms` answers, which is NOT what a refused send answers:
  /// `detail` is prose naming the member, and the only stable marker is the
  /// `error` token (`chat_api_cb_rooms_lifecycle:post_room_error_response`
  /// → `chat_api_rest_error:forbidden/2`). Every path that materializes a
  /// 1:1 room before sending meets this shape, so matching on `detail`
  /// alone left them all uncovered.
  const blockedRoomCreate = ChatForbiddenException(
    body: {
      'code': 403,
      'detail': 'Cannot create room with blocked user: u1',
      'error': 'blocked',
    },
    errorToken: 'blocked',
  );

  /// What every POST does. Swapped per test.
  late Future<Map<String, dynamic>> Function(
    String path,
    Map<String, dynamic> data,
  )
  onPost;

  Map<String, dynamic> serverMessage(Map<String, dynamic> data) => {
    'id': 'm-real',
    'from': 'me',
    'timestamp': '2026-01-01T00:00:00Z',
    'messageType': 'regular',
    'text': data['text'],
    'metadata': {'clientMessageId': data['clientMessageId']},
  };

  setUp(() {
    transport = _MockTransport();
    rest = _MockRest();
    store = MemoryChatLocalDatasource();
    events = StreamController<ChatEvent>.broadcast();
    states = StreamController<ChatConnectionState>.broadcast();
    onPost = (path, data) async => serverMessage(data);

    when(() => transport.events).thenAnswer((_) => events.stream);
    when(() => transport.stateChanges).thenAnswer((_) => states.stream);
    when(() => transport.state).thenReturn(ChatConnectionState.disconnected);
    when(() => transport.isWsConnected).thenReturn(false);
    when(() => transport.connect()).thenAnswer((_) async {});
    when(() => transport.disconnect()).thenAnswer((_) async {});
    when(() => transport.dispose()).thenAnswer((_) async {});
    when(() => transport.notifyTokenRotated()).thenAnswer((_) async {});
    when(() => rest.userId).thenReturn('me');

    when(
      () => rest.get(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.first as String;
      if (path == '/users/u1') {
        return {'id': 'u1', 'displayName': 'Alice'};
      }
      throw const ChatNotFoundException();
    });

    when(
      () => rest.post(
        any(),
        data: any(named: 'data'),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.first as String;
      final data =
          invocation.namedArguments[#data] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      return onPost(path, data);
    });

    client = NomaChatClient(
      config: ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: store,
        cacheConfig: const CacheConfig(),
      ),
      restClient: rest,
      transportManager: transport,
    );
    adapter = ChatUiAdapter(client: client, currentUser: me, cache: store);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
    await events.close();
    await states.close();
  });

  group('the rejection is swallowed on every send path', () {
    test(
      'a plain send leaves a sent bubble, no failure and no error',
      () async {
        await client.connect();
        final controller = adapter.getChatController('r1');
        final errors = <OperationError>[];
        final sub = adapter.operationErrors.listen(errors.add);
        addTearDown(sub.cancel);

        onPost = (path, data) async => throw blocked;
        final result = await adapter.messages.send('r1', text: 'ping');
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess, isTrue);
        final row = controller.messages.single;
        expect(row.receipt, ReceiptStatus.sent);
        expect(row.silentlyDropped, isTrue);
        expect(controller.isPending(row.id), isFalse);
        expect(controller.isFailed(row.id), isFalse);
        expect(errors, isEmpty);
      },
    );

    test(
      'the row is written to the cache, not only to the room preview',
      () async {
        await client.connect();
        adapter.getChatController('r1');

        onPost = (path, data) async => throw blocked;
        await adapter.messages.send('r1', text: 'ping');
        await Future<void>.delayed(Duration.zero);

        // The server has no record of it, so nothing else can ever bring it
        // back: without this write the sender reopens the room and finds the
        // message gone from the thread.
        final cached = (await store.getMessages('r1')).dataOrNull ?? const [];
        expect(cached.map((m) => m.text), ['ping']);
        expect(cached.single.silentlyDropped, isTrue);
        expect(cached.single.receipt, ReceiptStatus.sent);
        expect((await store.getPendingMessages('r1')).dataOrNull, isEmpty);
      },
    );

    test('a manual retry of a failed row is swallowed too', () async {
      await client.connect();
      final controller = adapter.getChatController('r1');

      onPost = (path, data) async =>
          throw const ChatApiException(statusCode: 500);
      await adapter.messages.send('r1', text: 'ping');
      final tempId = controller.messages.single.id;
      expect(controller.isFailed(tempId), isTrue);

      final errors = <OperationError>[];
      final sub = adapter.operationErrors.listen(errors.add);
      addTearDown(sub.cancel);
      onPost = (path, data) async => throw blocked;
      final retry = await adapter.messages.retrySend('r1', tempId);
      await Future<void>.delayed(Duration.zero);

      expect(retry.isSuccess, isTrue);
      expect(controller.isFailed(tempId), isFalse);
      expect(controller.messages.single.receipt, ReceiptStatus.sent);
      expect(controller.messages.single.silentlyDropped, isTrue);
      expect(errors, isEmpty);
    });

    test('the first message of a draft DM is swallowed when creating the '
        'room is what gets refused', () async {
      await client.connect();
      final draft = await adapter.dm.openDraft('u1');
      final key = adapter.dm.draftRoutingKey('u1');
      final errors = <OperationError>[];
      final sub = adapter.operationErrors.listen(errors.add);
      addTearDown(sub.cancel);

      onPost = (path, data) async {
        if (path == '/rooms') throw blockedRoomCreate;
        throw blocked;
      };
      final result = await adapter.messages.send(key, text: 'hola');
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      final row = draft.messages.single;
      expect(row.receipt, ReceiptStatus.sent);
      expect(row.silentlyDropped, isTrue);
      expect(draft.isFailed(row.id), isFalse);
      expect(errors, isEmpty);
    });

    test('the first message of a draft DM is swallowed when the '
        'contact-addressed fallback is what gets refused', () async {
      await client.connect();
      final draft = await adapter.dm.openDraft('u1');
      final key = adapter.dm.draftRoutingKey('u1');

      onPost = (path, data) async {
        if (path == '/rooms') throw const ChatNetworkException('offline');
        throw blocked;
      };
      final result = await adapter.messages.send(key, text: 'hola');
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      expect(draft.messages.single.receipt, ReceiptStatus.sent);
      expect(draft.messages.single.silentlyDropped, isTrue);
      expect(draft.isFailed(draft.messages.single.id), isFalse);
    });

    test('an attachment as the first message of a draft DM is swallowed '
        'when creating the room is what gets refused', () async {
      await client.connect();
      final draft = await adapter.dm.openDraft('u1');
      final key = adapter.dm.draftRoutingKey('u1');
      final errors = <OperationError>[];
      final sub = adapter.operationErrors.listen(errors.add);
      addTearDown(sub.cancel);

      onPost = (path, data) async => throw blockedRoomCreate;
      final result = await adapter.messages.sendAttachment(
        key,
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        fileName: 'a.png',
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      final row = draft.messages.single;
      expect(row.receipt, ReceiptStatus.sent);
      expect(row.silentlyDropped, isTrue);
      expect(draft.isFailed(row.id), isFalse);
      expect(errors, isEmpty);
    });

    test('a voice message as the first message of a draft DM is swallowed '
        'when creating the room is what gets refused', () async {
      await client.connect();
      final draft = await adapter.dm.openDraft('u1');
      final key = adapter.dm.draftRoutingKey('u1');
      final errors = <OperationError>[];
      final sub = adapter.operationErrors.listen(errors.add);
      addTearDown(sub.cancel);

      onPost = (path, data) async => throw blockedRoomCreate;
      final result = await adapter.messages.sendVoice(
        key,
        audioBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/mp4',
        duration: const Duration(seconds: 2),
        waveform: const [1, 2, 3],
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      final row = draft.messages.single;
      expect(row.receipt, ReceiptStatus.sent);
      expect(row.silentlyDropped, isTrue);
      expect(draft.isFailed(row.id), isFalse);
      expect(errors, isEmpty);
    });

    test('a forward whose target is a draft DM is swallowed when creating '
        'the room is what gets refused', () async {
      await client.connect();
      final draft = await adapter.dm.openDraft('u1');
      final key = adapter.dm.draftRoutingKey('u1');
      final errors = <OperationError>[];
      final sub = adapter.operationErrors.listen(errors.add);
      addTearDown(sub.cancel);

      onPost = (path, data) async => throw blockedRoomCreate;
      final results = await adapter.messages.forward(
        sourceRoomId: 'r1',
        messageId: 'm-src',
        targetRoomIds: [key],
      );
      await Future<void>.delayed(Duration.zero);

      expect(results.single.isSuccess, isTrue);
      final row = draft.messages.single;
      expect(row.receipt, ReceiptStatus.sent);
      expect(row.silentlyDropped, isTrue);
      expect(draft.isFailed(row.id), isFalse);
      expect(errors, isEmpty);
    });

    test('a 403 that is not a block still fails the bubble', () async {
      await client.connect();
      final controller = adapter.getChatController('r1');

      onPost = (path, data) async => throw const ChatForbiddenException(
        body: {'code': 403, 'detail': 'muted'},
      );
      final result = await adapter.messages.send('r1', text: 'ping');
      await Future<void>.delayed(Duration.zero);

      expect(result.isFailure, isTrue);
      final row = controller.messages.single;
      expect(controller.isFailed(row.id), isTrue);
      expect(row.silentlyDropped, isFalse);
    });
  });

  group('the swallowed row never advances past one tick', () {
    test('a later delivery cursor does not turn it into ✓✓', () async {
      await client.connect();
      final controller = adapter.getChatController('r1');

      onPost = (path, data) async => throw blocked;
      await adapter.messages.send('r1', text: 'ping');
      await Future<void>.delayed(Duration.zero);
      final tempId = controller.messages.single.id;

      controller.applyDeliveryCursor(userId: 'u1', messageId: tempId);
      controller.updateReceipt('temp', ReceiptStatus.read, fromUserId: 'u1');

      expect(controller.receiptStatuses[tempId], isNull);
      expect(controller.messages.single.receipt, ReceiptStatus.sent);
    });
  });
}
