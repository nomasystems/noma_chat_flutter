import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// One rule across every surface that paints a person: an id is not a name.
/// When nobody — host directory, chat profile, host resolver — can name an
/// id, the SDK leaves the slot empty and lets the host put its own
/// placeholder there. It never spells out the UUID.
class _FakeBlockedContacts implements ChatContactsApi {
  _FakeBlockedContacts(this._blocked);
  final List<String> _blocked;

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async => ChatSuccess(
    ChatPaginatedResponse(items: List<String>.of(_blocked), hasMore: false),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockedOnlyClient implements ChatClient {
  _BlockedOnlyClient(this.contacts);

  @override
  final ChatContactsApi contacts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const nameless = 'a5f3c9d1-0000-4000-8000-000000000001';

  group('GroupMembersView', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'Team', members: ['me', nameless]),
      );
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    Widget wrap({String? Function(String)? names}) => MaterialApp(
      home: Scaffold(
        body: GroupMembersView(
          adapter: adapter,
          roomId: 'r1',
          currentUserRole: RoomRole.member,
          displayNameResolver: names,
        ),
      ),
    );

    testWidgets('a member nobody can name is never listed by id', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(nameless), findsNothing);
    });

    testWidgets('a resolved name is still shown', (tester) async {
      await tester.pumpWidget(
        wrap(names: (id) => id == nameless ? 'Alice' : null),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text(nameless), findsNothing);
    });
  });

  group('BlockedUsersView', () {
    testWidgets('a blocked id nobody can name is never listed by id', (
      tester,
    ) async {
      final client = _BlockedOnlyClient(_FakeBlockedContacts([nameless]));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BlockedUsersView(client: client)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nameless), findsNothing);
    });

    testWidgets('a resolved name is still shown', (tester) async {
      final client = _BlockedOnlyClient(_FakeBlockedContacts([nameless]));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockedUsersView(
              client: client,
              displayNameResolver: (id) => 'Bob',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(nameless), findsNothing);
    });
  });

  group('MessageInput mentions', () {
    testWidgets('picking a nameless candidate writes no id into the message', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [ChatUser(id: nameless)],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: MessageInput(
                controller: controller,
                onSendMessageRequest: (_) => true,
                enableMentions: true,
                mentionUsers: const [ChatUser(id: nameless)],
              ),
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '@');
      await tester.pump();
      expect(find.byType(MentionOverlay), findsOneWidget);

      await tester.tap(find.byType(ListTile).first);
      await tester.pump();

      final text = tester.widget<TextField>(field).controller!.text;
      expect(text, '@');
      expect(text.contains(nameless), isFalse);
      expect(find.byType(MentionOverlay), findsNothing);
    });

    testWidgets('a named candidate is still inserted', (tester) async {
      const alice = ChatUser(id: 'u1', displayName: 'Alice');
      final controller = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [alice],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: MessageInput(
                controller: controller,
                onSendMessageRequest: (_) => true,
                enableMentions: true,
                mentionUsers: const [alice],
              ),
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '@a');
      await tester.pump();
      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(tester.widget<TextField>(field).controller!.text, '@Alice ');
    });

    testWidgets('the composer resolver names a candidate its profile cannot', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [ChatUser(id: nameless)],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: MessageInput(
                controller: controller,
                onSendMessageRequest: (_) => true,
                enableMentions: true,
                mentionUsers: const [ChatUser(id: nameless)],
                displayNameResolver: (id) => id == nameless ? 'Carol' : null,
              ),
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '@');
      await tester.pump();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();

      expect(tester.widget<TextField>(field).controller!.text, '@Carol ');
    });
  });

  group('MessageInfoSheet', () {
    testWidgets('a receipt row with no resolver carries no id', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageInfoSheet(
              message: ChatMessage(
                id: 'm1',
                from: 'me',
                timestamp: DateTime(2026, 1, 1),
                text: 'hi',
              ),
              currentUserId: 'me',
              receipts: [
                ReadReceipt(
                  userId: nameless,
                  lastReadAt: DateTime.utc(2026, 1, 1, 10),
                  lastDeliveredAt: DateTime.utc(2026, 1, 1, 10),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nameless), findsNothing);
    });
  });

  group('ReactionDetailContent', () {
    final reactions = [
      const AggregatedReaction(emoji: '\u{1F44D}', count: 1, users: [nameless]),
    ];

    testWidgets('a fetcher that throws leaves the reactor unnamed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionDetailContent(
              fetchReactions: () async => reactions,
              currentUserId: 'me',
              userFetcher: (_) async => throw StateError('offline'),
              onRemoveReaction: (_) {},
              theme: ChatTheme.defaults,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nameless), findsNothing);
    });

    testWidgets('a batch fetcher that skips an id leaves it unnamed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionDetailContent(
              fetchReactions: () async => reactions,
              currentUserId: 'me',
              userFetcher: (id) async =>
                  ReactionUser(id: id, displayName: 'never called'),
              batchUserFetcher: (_) async => const {},
              onRemoveReaction: (_) {},
              theme: ChatTheme.defaults,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nameless), findsNothing);
    });
  });
}
