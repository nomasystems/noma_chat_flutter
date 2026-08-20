import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The pruning of blocked content, mounted the way the package mounts it:
/// a [NomaChatView] over a real adapter for the room surfaces and a
/// [RoomListView] over the same adapter for the list. A [MessageList] built
/// by hand answers for the bubble and nothing else — and the bubble was
/// never the whole leak: the quote, the reactions and the room-list preview
/// each carried the blocked sender's content past it, and a 1:1 was being
/// pruned when it should only ever have shown its banner.
void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  const blockedId = 'u2';
  const blockedLabel = 'Message from a blocked user';
  const roomNotice = 'You blocked someone in this chat';

  Widget wrap(Widget child) => MaterialApp(home: child);

  /// Message bodies render as rich text (links, mentions, markdown), so a
  /// plain `find.text` neither finds them nor proves their absence.
  Finder body(String text) => find.textContaining(text, findRichText: true);

  ChatMessage blockedText(String id, String text) => ChatMessage(
    id: id,
    from: blockedId,
    text: text,
    timestamp: DateTime(2026, 1, 1, 10),
  );

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
    adapter.blockedUserIds = {blockedId};
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  Future<void> pumpRoom(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        NomaChatView(
          roomId: 'room1',
          adapter: adapter,
          hydrateGroupMembers: false,
        ),
      ),
    );
    await tester.pump();
  }

  group('a 1:1 with a blocked contact', () {
    setUp(() {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Bob', otherUserId: blockedId),
      );
    });

    testWidgets('keeps its history — the banner is the whole behaviour', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [blockedText('m1', 'what bob wrote')],
      );

      await pumpRoom(tester);

      expect(body('what bob wrote'), findsWidgets);
      expect(find.text(blockedLabel), findsNothing);
      expect(find.byType(BlockedChatBanner), findsOneWidget);
    });

    testWidgets('shows no room notice: it is not pruning anything', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [blockedText('m1', 'what bob wrote')],
      );

      await pumpRoom(tester);

      expect(find.text(roomNotice), findsNothing);
    });

    testWidgets('keeps the quote of a blocked message intact', (tester) async {
      adapter.getChatController(
        'room1',
        initialMessages: [
          blockedText('m1', 'quoted words'),
          ChatMessage(
            id: 'm2',
            from: 'u1',
            text: 'my answer',
            messageType: MessageType.reply,
            referencedMessageId: 'm1',
            timestamp: DateTime(2026, 1, 1, 10, 1),
          ),
        ],
      );

      await pumpRoom(tester);

      expect(body('quoted words'), findsWidgets);
    });
  });

  group('a group with a blocked member', () {
    setUp(() {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );
    });

    testWidgets('prunes what they wrote and says out loud that it does', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [
          blockedText('m1', 'secret from the blocked one'),
          ChatMessage(
            id: 'm2',
            from: blockedId,
            timestamp: DateTime(2026, 1, 1, 10, 1),
            messageType: MessageType.location,
            metadata: const {'lat': 40.4, 'lng': -3.7},
          ),
        ],
      );

      await pumpRoom(tester);

      expect(body('secret from the blocked one'), findsNothing);
      expect(find.text(blockedLabel), findsNWidgets(2));
      expect(find.text(roomNotice), findsOneWidget);
    });

    testWidgets('drops the notice when the blocked member never spoke here', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u3',
            text: 'only carol here',
            timestamp: DateTime(2026, 1, 1, 10),
          ),
        ],
      );

      await pumpRoom(tester);

      expect(find.text(roomNotice), findsNothing);
      expect(body('only carol here'), findsWidgets);
    });

    testWidgets('prunes the quote a reply carries of a blocked message', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [
          blockedText('m1', 'quoted words'),
          ChatMessage(
            id: 'm2',
            from: 'u3',
            text: 'answering that',
            messageType: MessageType.reply,
            referencedMessageId: 'm1',
            timestamp: DateTime(2026, 1, 1, 10, 1),
          ),
        ],
      );

      await pumpRoom(tester);

      expect(body('quoted words'), findsNothing);
      expect(body('answering that'), findsWidgets);
      // The row itself plus the strip inside the reply bubble.
      expect(find.text(blockedLabel), findsNWidgets(2));
    });

    testWidgets('subtracts the reactions a blocked user left on my message', (
      tester,
    ) async {
      final controller = adapter.getChatController(
        'room1',
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u1',
            text: 'mine',
            timestamp: DateTime(2026, 1, 1, 10),
            metadata: const {
              '_reactionUsers': {
                '👍': [blockedId, 'u3'],
                '😂': [blockedId],
              },
            },
          ),
        ],
      );
      controller.setReactions('m1', {'👍': 2, '😂': 1});

      await pumpRoom(tester);

      expect(find.text('👍 1'), findsOneWidget);
      expect(find.text('👍 2'), findsNothing);
      expect(find.text('😂 1'), findsNothing);
    });

    testWidgets('leaves anonymous reaction counts alone rather than guess', (
      tester,
    ) async {
      final controller = adapter.getChatController(
        'room1',
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u1',
            text: 'mine',
            timestamp: DateTime(2026, 1, 1, 10),
          ),
        ],
      );
      controller.setReactions('m1', {'👍': 2});

      await pumpRoom(tester);

      expect(find.text('👍 2'), findsOneWidget);
    });
  });

  group('the reaction detail sheet', () {
    testWidgets('lists the reactors the chip counts, and no one else', (
      tester,
    ) async {
      final controller = ChatController(
        currentUser: currentUser,
        otherUsers: const [
          ChatUser(id: blockedId, displayName: 'Bob'),
          ChatUser(id: 'u3', displayName: 'Carol'),
        ],
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u1',
            text: 'mine',
            timestamp: DateTime(2026, 1, 1, 10),
            metadata: const {
              '_reactionUsers': {
                '👍': [blockedId, 'u3'],
              },
            },
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ChatView(
              controller: controller,
              behaviors: const ChatViewBehaviors(
                isGroup: true,
                blockedSenderIds: {blockedId},
                messageReactions: {
                  'm1': {'👍': 2},
                },
              ),
              builders: ChatViewBuilders(
                userFetcher: (id) async => ReactionUser(
                  id: id,
                  displayName: id == blockedId ? 'Bob' : 'Carol',
                ),
              ),
              callbacks: ChatViewCallbacks(
                onFetchReactions: (_) async => const [
                  AggregatedReaction(
                    emoji: '👍',
                    count: 2,
                    users: [blockedId, 'u3'],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('👍 1'), findsOneWidget);

      await tester.tap(find.text('👍 1'));
      await tester.pumpAndSettle();

      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });
  });

  group('the room list preview', () {
    Future<void> pumpList(WidgetTester tester, {Widget? view}) async {
      await tester.pumpWidget(
        wrap(
          view ??
              RoomListView(
                controller: adapter.roomListController,
                adapter: adapter,
                currentUserId: 'u1',
                showHeader: false,
                showSearch: false,
              ),
        ),
      );
      await tester.pump();
    }

    testWidgets('stops quoting the blocked sender on a group row', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          lastMessage: 'secret from the blocked one',
          lastMessageUserId: blockedId,
          lastMessageSenderName: 'Bob',
        ),
      );

      await pumpList(tester);

      expect(body('secret from the blocked one'), findsNothing);
      expect(body('Bob:'), findsNothing);
      expect(find.text(blockedLabel), findsOneWidget);
    });

    testWidgets('leaves a DM row alone — that chat keeps its history', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Bob',
          otherUserId: blockedId,
          lastMessage: 'what bob wrote',
          lastMessageUserId: blockedId,
        ),
      );

      await pumpList(tester);

      expect(body('what bob wrote'), findsWidgets);
      expect(find.text(blockedLabel), findsNothing);
    });

    testWidgets('hide leaves the group row mute instead of pruning the row', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          lastMessage: 'secret from the blocked one',
          lastMessageUserId: blockedId,
        ),
      );

      await pumpList(
        tester,
        view: RoomListView(
          controller: adapter.roomListController,
          adapter: adapter,
          currentUserId: 'u1',
          showHeader: false,
          showSearch: false,
          blockedContentPolicy: BlockedContentPolicy.hide,
        ),
      );

      expect(find.text('Team'), findsOneWidget);
      expect(body('secret from the blocked one'), findsNothing);
      expect(find.text(blockedLabel), findsNothing);
    });

    testWidgets('show prints the preview verbatim', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          lastMessage: 'secret from the blocked one',
          lastMessageUserId: blockedId,
        ),
      );

      await pumpList(
        tester,
        view: RoomListView(
          controller: adapter.roomListController,
          adapter: adapter,
          currentUserId: 'u1',
          showHeader: false,
          showSearch: false,
          blockedContentPolicy: BlockedContentPolicy.show,
        ),
      );

      expect(body('secret from the blocked one'), findsWidgets);
    });
  });
}
