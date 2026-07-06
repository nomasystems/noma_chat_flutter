import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  group('NomaChat.create', () {
    late NomaChat chat;

    tearDown(() async {
      await chat.dispose();
    });

    Future<NomaChat> buildChat({
      ChatUiLocalizations l10n = ChatUiLocalizations.en,
    }) => NomaChat.create(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
      currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      enableCache: false,
      localDatasource: MemoryChatLocalDatasource(),
      l10n: l10n,
    );

    test('wires a NomaChatClient and a UI adapter from a ChatConfig', () async {
      chat = await buildChat();

      expect(chat.client, isA<NomaChatClient>());
      expect(chat.adapter, isNotNull);
      expect(chat.adapter.client, same(chat.client));
      expect(chat.roomListController, isNotNull);
      expect(chat.connectionState.value, ChatConnectionState.disconnected);
    });

    test('threads the supplied l10n through to the adapter', () async {
      chat = await buildChat(l10n: ChatUiLocalizations.es);

      expect(chat.adapter.l10n, ChatUiLocalizations.es);
    });
  });

  group('NomaChat.fromConfig', () {
    late NomaChat chat;

    tearDown(() async {
      await chat.dispose();
    });

    test('builds from a ChatConfig without restated connection params',
        () async {
      final config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: MemoryChatLocalDatasource(),
      );

      chat = await NomaChat.fromConfig(
        config: config,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      expect(chat.client, isA<NomaChatClient>());
      expect(chat.adapter.client, same(chat.client));
      expect(chat.connectionState.value, ChatConnectionState.disconnected);
    });

    test('adapter currentUser reflects the supplied user', () async {
      final config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: MemoryChatLocalDatasource(),
      );

      chat = await NomaChat.fromConfig(
        config: config,
        currentUser: const ChatUser(id: 'u42', displayName: 'Config User'),
      );

      expect(chat.adapter.currentUser.id, 'u42');
      expect(chat.adapter.currentUser.displayName, 'Config User');
    });

    test('threads the supplied l10n through to the adapter', () async {
      final config = ChatConfig(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        tokenProvider: () async => 't',
        localDatasource: MemoryChatLocalDatasource(),
      );

      chat = await NomaChat.fromConfig(
        config: config,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
        l10n: ChatUiLocalizations.es,
      );

      expect(chat.adapter.l10n, ChatUiLocalizations.es);
    });
  });

  group('NomaChat.fromClient', () {
    test('creates instance with MockChatClient', () {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      expect(chat.client, same(client));
      expect(chat.adapter, isNotNull);
      expect(chat.roomListController, isNotNull);
      expect(chat.connectionState.value, ChatConnectionState.disconnected);
    });

    test('accepts custom l10n', () {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
        l10n: ChatUiLocalizations.es,
      );

      expect(chat.adapter.l10n, ChatUiLocalizations.es);
    });

    test('connect delegates to adapter', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      await chat.connect();
      expect(chat.connectionState.value, ChatConnectionState.connected);
    });

    test('disconnect delegates to adapter', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      await chat.connect();
      await chat.disconnect();
      expect(chat.connectionState.value, ChatConnectionState.disconnected);
    });

    test('dispose cleans up adapter', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      await chat.connect();
      await chat.dispose();
    });
  });
}
