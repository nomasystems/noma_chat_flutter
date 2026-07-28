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

/// A DM starts as a purely local draft: no room exists server-side until
/// the first message is sent. Both tests here cover what happens when that
/// very first send cannot materialize the room.
void main() {
  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;
  late NomaChatClient client;
  late ChatUiAdapter adapter;

  const me = ChatUser(id: 'me', displayName: 'Me');

  /// `true` while the device is "offline": every POST fails the way a
  /// connectivity drop does, so `rooms.create` cannot materialize the DM.
  var offline = true;

  setUp(() {
    offline = true;
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
      throw const ChatNetworkException('offline');
    });

    when(
      () => rest.post(
        any(),
        data: any(named: 'data'),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((invocation) async {
      if (offline) throw const ChatNetworkException('offline');
      final path = invocation.positionalArguments.first as String;
      final data = invocation.namedArguments[#data] as Map<String, dynamic>;
      if (path == '/rooms') {
        return {'id': 'r-real', 'audience': 'unrestricted'};
      }
      return {
        'id': 'm1',
        'from': 'me',
        'timestamp': '2025-01-01T00:00:00Z',
        'messageType': 'regular',
        'text': data['text'],
        'metadata': {'clientMessageId': data['clientMessageId']},
      };
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
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
    await events.close();
    await states.close();
  });

  test('the first message of a brand-new DM sent while offline is queued as a '
      'contact-addressed send and lands once the connection returns', () async {
    await client.connect();

    final draft = await adapter.dm.openDraft('u1');
    final key = adapter.dm.draftRoutingKey('u1');

    final result = await adapter.messages.send(key, text: 'hola');
    expect(result.isFailure, isTrue);

    final tempId = draft.messages.single.id;
    expect(draft.isFailed(tempId), isTrue);

    // The regression: the draft has no room id, so nothing could enter the
    // room-keyed offline queue and the message was lost for good. It must
    // now be durable as a contact-addressed operation instead.
    final queued = (await store.getOfflineQueue()).dataOrNull ?? const [];
    expect(queued, hasLength(1));
    expect(queued.single['type'], 'sendDirectMessage');
    expect(queued.single['contactUserId'], 'u1');
    expect(queued.single['text'], 'hola');
    // Same idempotency key as the optimistic bubble, so the drain cannot
    // duplicate a send that had actually landed.
    expect(queued.single['clientMessageId'], tempId);

    // Reconnect: the queued operation resolves the 1:1 room server-side.
    offline = false;
    await client.flushPendingOperations();

    verify(
      () => rest.post(
        '/contacts/u1/messages',
        data: any(named: 'data'),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).called(greaterThanOrEqualTo(1));
    expect((await store.getOfflineQueue()).dataOrNull ?? const [], isEmpty);
  });

  test('retrying a failed message of a still-draft DM materializes the room '
      'and posts to the real room id', () async {
    await client.connect();

    final draft = await adapter.dm.openDraft('u1');
    final key = adapter.dm.draftRoutingKey('u1');

    await adapter.messages.send(key, text: 'hola');
    final tempId = draft.messages.single.id;
    expect(draft.isFailed(tempId), isTrue);
    expect(draft.isDraft, isTrue);

    offline = false;
    final retry = await adapter.messages.retrySend(key, tempId);

    expect(retry.isSuccess, isTrue);
    // The regression: the retry used to be posted against the synthetic
    // `draft:u1` routing key, a room that does not exist server-side, so
    // it could never converge.
    verify(
      () => rest.post(
        '/rooms/r-real/messages',
        data: any(named: 'data'),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).called(1);
    verifyNever(
      () => rest.post(
        '/rooms/$key/messages',
        data: any(named: 'data'),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    );
    expect(draft.isDraft, isFalse);
    expect(draft.roomId, 'r-real');
    expect(adapter.getChatController('r-real'), same(draft));
  });
}
