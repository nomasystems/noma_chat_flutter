import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
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
      expect(
        chat.connectionState.value,
        ChatConnectionState.connected,
      );
    });

    test('disconnect delegates to adapter', () async {
      final client = MockChatClient(currentUserId: 'u1');
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Test'),
      );

      await chat.connect();
      await chat.disconnect();
      expect(
        chat.connectionState.value,
        ChatConnectionState.disconnected,
      );
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
