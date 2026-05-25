import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  group('SuggestionBarController.load — roster', () {
    test('populates suggestions from contacts and excludes self', () async {
      await client.contacts.add('u1');
      await client.contacts.add('u2');
      await client.contacts.add('me'); // self → excluded
      adapter.cacheUsers(const [
        ChatUser(id: 'u1', displayName: 'Alice', avatarUrl: 'a.png'),
        ChatUser(id: 'u2', displayName: 'Bob'),
      ]);

      final controller = SuggestionBarController(adapter);
      addTearDown(controller.dispose);

      await controller.load();

      final ids = controller.suggestions.map((s) => s.id).toList();
      expect(ids, containsAll(<String>['u1', 'u2']));
      expect(ids, isNot(contains('me')));
      expect(controller.isLoading, isFalse);
    });
  });

  group('SuggestionBarController.load — discovery + demo names', () {
    test('discoverAll lists every active user via an empty search', () async {
      client
        ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'))
        ..seedUser(const ChatUser(id: 'u2', displayName: 'Bob'));

      final controller = SuggestionBarController(adapter, discoverAll: true);
      addTearDown(controller.dispose);

      await controller.load();

      final ids = controller.suggestions.map((s) => s.id).toList();
      expect(ids, containsAll(<String>['u1', 'u2']));
      expect(ids, isNot(contains('me')));
    });

    test(
      'resolves configured demo names by exact display-name match',
      () async {
        client.seedUser(const ChatUser(id: 'u9', displayName: 'newsroom'));

        final controller = SuggestionBarController(
          adapter,
          demoDisplayNames: const ['newsroom'],
        );
        addTearDown(controller.dispose);

        await controller.load();

        expect(controller.suggestions.any((s) => s.id == 'u9'), isTrue);
      },
    );
  });

  group('SuggestionBarController — static + lifecycle', () {
    test('setStatic replaces the snapshot and notifies listeners', () {
      final controller = SuggestionBarController(adapter);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setStatic(const [
        SuggestedContact(id: 'x', displayName: 'Static'),
      ]);

      expect(controller.suggestions.single.id, 'x');
      expect(notifications, greaterThan(0));
    });

    test('startAutoRefresh + stopAutoRefresh are safe and idempotent', () {
      final controller = SuggestionBarController(adapter);
      addTearDown(controller.dispose);

      controller.startAutoRefresh(interval: const Duration(milliseconds: 50));
      controller.stopAutoRefresh();
      controller.stopAutoRefresh();
    });
  });

  group('demoContactsFromEnvironment', () {
    test('returns an empty list when DEMO_CONTACTS is unset', () {
      expect(demoContactsFromEnvironment(), isEmpty);
    });
  });
}
