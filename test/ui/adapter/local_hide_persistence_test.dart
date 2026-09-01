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

/// "Delete for me" over a tombstone, for a host that wires its local
/// datasource at the client level and builds the adapter without a
/// `cache:` argument — WB's exact setup.
///
/// The backend has no per-user hide state, so the marker is the only
/// thing standing between the user and the tombstone they just dismissed:
/// the very next list fetch hands it straight back.
void main() {
  late _MockTransport transport;
  late _MockRest rest;
  late MemoryChatLocalDatasource store;
  late StreamController<ChatEvent> events;
  late StreamController<ChatConnectionState> states;
  late NomaChatClient client;

  const me = ChatUser(id: 'me', displayName: 'Me');

  /// What `GET /rooms/{id}/messages` answers: a live row and a globally
  /// soft-deleted one. The tombstone is the only row WB offers
  /// "Delete for me" on (`chat_room_message_menu.dart`, gated on
  /// `message.isDeleted`).
  Map<String, dynamic> serverPage() => {
    'messages': [
      {
        'id': 'm-keep',
        'from': 'u1',
        'timestamp': '2026-01-01T00:00:01Z',
        'messageType': 'regular',
        'text': 'still here',
      },
      {
        'id': 'm-gone',
        'from': 'u1',
        'timestamp': '2026-01-01T00:00:02Z',
        'messageType': 'regular',
        'text': null,
        'isDeleted': true,
      },
    ],
    'hasMore': false,
  };

  ChatUiAdapter bareAdapter() {
    // Deliberately no `cache:` — mirrors WB's exact setup, where every
    // `cache?.…` write in the adapter is a silent no-op.
    final a = ChatUiAdapter(client: client, currentUser: me);
    a.start();
    addTearDown(a.dispose);
    return a;
  }

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
    when(() => rest.userId).thenReturn('me');

    when(
      () => rest.get(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.first as String;
      if (path == '/rooms/r1/messages') return serverPage();
      if (path == '/users/u1') return {'id': 'u1', 'displayName': 'Alice'};
      throw const ChatNotFoundException();
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
  });

  tearDown(() async {
    await client.dispose();
    await events.close();
    await states.close();
  });

  group('delete for me, host without an adapter cache', () {
    test('the hidden marker is written through the client surface', () async {
      await client.connect();
      final adapter = bareAdapter();
      await adapter.messages.load('r1');

      await adapter.deleteMessageLocally('r1', 'm-gone');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final hidden = (await store.getHiddenMessageIds('r1')).dataOrNull;
      expect(hidden, contains('m-gone'));
    });

    // Was: back on every fetch, because the marker was never persisted.
    test('the tombstone stays gone when the room is reopened', () async {
      await client.connect();
      final adapter = bareAdapter();
      final controller = adapter.getChatController('r1');
      await adapter.messages.load('r1');
      expect(controller.messages.map((m) => m.id), [
        'm-keep',
        'm-gone',
      ], reason: 'both rows come down from the server to begin with');

      await adapter.deleteMessageLocally('r1', 'm-gone');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.messages.map((m) => m.id), ['m-keep']);

      // Reopen from scratch: only what the client-level datasource holds
      // survives. The server still serves the tombstone on every fetch.
      final reopened = bareAdapter();
      final fresh = reopened.getChatController('r1');
      final load = await reopened.messages.load('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(load.isSuccess, isTrue);
      expect(fresh.messages.map((m) => m.id), ['m-keep']);
    });
  });
}
