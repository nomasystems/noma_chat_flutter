import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Widget tests for [UserInfoPage] — the read-only "user info" page for a
/// DM peer. Hydrates from the adapter cache for instant paint, then always
/// refreshes from `client.users.get`.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final l10n = ChatTheme.defaults.l10n;

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

  Widget wrap(String userId) => MaterialApp(
    home: UserInfoPage(adapter: adapter, userId: userId),
  );

  group('UserInfoPage — load states', () {
    testWidgets('shows a spinner before the peer resolves', (tester) async {
      client.seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));

      await tester.pumpWidget(wrap('u1'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders the profile title and the peer display name', (
      tester,
    ) async {
      client.seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));

      await tester.pumpWidget(wrap('u1'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.profile), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows an error message when the peer cannot be loaded', (
      tester,
    ) async {
      // 'ghost' is neither cached nor seeded → users.get fails.
      await tester.pumpWidget(wrap('ghost'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Not found'), findsOneWidget);
    });

    testWidgets('falls back to the raw id when display name is empty', (
      tester,
    ) async {
      client.seedUser(const ChatUser(id: 'u3', displayName: ''));

      await tester.pumpWidget(wrap('u3'));
      await tester.pumpAndSettle();

      expect(find.text('u3'), findsOneWidget);
    });
  });

  group('UserInfoPage — bio section', () {
    testWidgets('renders the about section when a bio is present', (
      tester,
    ) async {
      client.seedUser(
        const ChatUser(id: 'u1', displayName: 'Alice', bio: 'Loves cats'),
      );

      await tester.pumpWidget(wrap('u1'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.about), findsOneWidget);
      expect(find.text('Loves cats'), findsOneWidget);
    });

    testWidgets('omits the about section when there is no bio', (tester) async {
      client.seedUser(const ChatUser(id: 'u2', displayName: 'Bob'));

      await tester.pumpWidget(wrap('u2'));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(l10n.about), findsNothing);
    });
  });

  group('UserInfoPage — cache then refresh', () {
    testWidgets('paints from cache then overwrites with the backend record', (
      tester,
    ) async {
      adapter.cacheUsers(const [
        ChatUser(id: 'u1', displayName: 'Alice', bio: 'cached bio'),
      ]);
      client.seedUser(
        const ChatUser(id: 'u1', displayName: 'Alice', bio: 'fresh bio'),
      );

      await tester.pumpWidget(wrap('u1'));
      await tester.pumpAndSettle();

      // The always-on backend refresh wins over the cached entry.
      expect(find.text('fresh bio'), findsOneWidget);
      expect(find.text('cached bio'), findsNothing);
    });
  });
}
