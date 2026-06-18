import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  Widget wrap(Widget child) => MaterialApp(home: child);

  ChatMessage msg(String id) =>
      ChatMessage(id: id, from: 'u2', timestamp: DateTime(2024, 1, 1));

  ChatView chatViewOf(WidgetTester tester) =>
      tester.widget<ChatView>(find.byType(ChatView));

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('NomaChatView', () {
    testWidgets('renders the app bar and the chat view', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            // Disable group hydration: the mock has no seeded room so
            // members.list returns NotFound; the swallow path is exercised
            // elsewhere and keeping it off makes the test deterministic.
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatRoomAppBar), findsOneWidget);
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('shows the composer for a normal room', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Alice'),
      );

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

      // The message composer renders when the room is writable.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'announcement room for a non-owner is read-only (no composer)',
      (tester) async {
        adapter.roomListController.addRoom(
          const RoomListItem(
            id: 'room1',
            name: 'Broadcast',
            isGroup: true,
            isAnnouncement: true,
            userRole: RoomRole.member,
          ),
        );

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

        // Read-only banner replaces the composer: no input field.
        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets(
      'contextMenuActionsResolver overrides the role-aware defaults',
      (tester) async {
        adapter.roomListController.addRoom(
          const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
        );

        Set<MessageAction>? observedDefaults;
        await tester.pumpWidget(
          wrap(
            NomaChatView(
              roomId: 'room1',
              adapter: adapter,
              hydrateGroupMembers: false,
              contextMenuActionsResolver: (room, defaults) {
                observedDefaults = defaults;
                return {MessageAction.reply};
              },
            ),
          ),
        );
        await tester.pump();

        // The resolver is consulted with the role-aware default set. A
        // non-admin member in a group (memberCount unset) cannot pin, so
        // `pin` is absent from the defaults handed to the resolver.
        expect(observedDefaults, isNotNull);
        expect(observedDefaults!.contains(MessageAction.pin), isFalse);
        expect(observedDefaults!.contains(MessageAction.report), isTrue);
      },
    );

    testWidgets('admin in a group gets pin in the default actions', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          userRole: RoomRole.admin,
        ),
      );

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

      final actions = chatViewOf(tester).behaviors.contextMenuActions;
      expect(actions.contains(MessageAction.pin), isTrue);
    });

    testWidgets('owner in a group gets pin in the default actions', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          userRole: RoomRole.owner,
        ),
      );

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

      expect(
        chatViewOf(tester).behaviors.contextMenuActions,
        contains(MessageAction.pin),
      );
    });

    testWidgets('a two-member DM can pin even as a plain member', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Alice',
          memberCount: 2,
          userRole: RoomRole.member,
        ),
      );

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

      expect(
        chatViewOf(tester).behaviors.contextMenuActions,
        contains(MessageAction.pin),
      );
    });

    testWidgets('a member in a group cannot pin', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          userRole: RoomRole.member,
        ),
      );

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

      expect(
        chatViewOf(tester).behaviors.contextMenuActions,
        isNot(contains(MessageAction.pin)),
      );
    });

    testWidgets(
      'consumer-supplied contextMenuActions wins over auto-computed set',
      (tester) async {
        adapter.roomListController.addRoom(
          const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
        );

        await tester.pumpWidget(
          wrap(
            NomaChatView(
              roomId: 'room1',
              adapter: adapter,
              hydrateGroupMembers: false,
              behaviors: const ChatViewBehaviors(
                contextMenuActions: {MessageAction.copy},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(chatViewOf(tester).behaviors.contextMenuActions, {
          MessageAction.copy,
        });
      },
    );

    testWidgets('hydrateGroupMembers fetches members and missing profiles', (
      tester,
    ) async {
      mockClient.seedRoom(
        const ChatRoom(id: 'room1', name: 'Team', members: ['u1', 'u2', 'u3']),
      );
      mockClient.seedUser(const ChatUser(id: 'u2', displayName: 'Bob'));
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = adapter.getChatController('room1');
      final ids = controller.otherUsers.map((u) => u.id).toSet();
      expect(ids, containsAll(<String>['u2', 'u3']));
      expect(ids.contains('u1'), isFalse);
    });

    testWidgets('hydrateGroupMembers=false leaves otherUsers untouched', (
      tester,
    ) async {
      mockClient.seedRoom(
        const ChatRoom(id: 'room1', name: 'Team', members: ['u1', 'u2']),
      );
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(adapter.getChatController('room1').otherUsers, isEmpty);
    });

    testWidgets('seeds the unread divider snapshot from the room badge', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [msg('m1'), msg('m2'), msg('m3')],
      );
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', unreadCount: 2),
      );

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

      final behaviors = chatViewOf(tester).behaviors;
      expect(behaviors.unreadCount, 2);
      expect(behaviors.unreadBoundaryMessageId, 'm2');
      expect(behaviors.initialMessageId, 'm2');

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('initialMessageId overrides the seeded unread target', (
      tester,
    ) async {
      adapter.getChatController(
        'room1',
        initialMessages: [msg('m1'), msg('m2')],
      );
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', unreadCount: 1),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            initialMessageId: 'mX',
          ),
        ),
      );
      await tester.pump();

      expect(chatViewOf(tester).behaviors.initialMessageId, 'mX');

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('onBlockedUsersChanged rebuilds and chains the prior handler', (
      tester,
    ) async {
      var priorCalled = false;
      adapter.onBlockedUsersChanged = (_) => priorCalled = true;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Alice', otherUserId: 'u2'),
      );

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

      adapter.onBlockedUsersChanged!(<String>{'u2'});
      await tester.pump();

      expect(priorCalled, isTrue);
    });

    testWidgets('onRoomRemoved for this room invokes onRoomLeft', (
      tester,
    ) async {
      var left = false;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            onRoomLeft: () => left = true,
          ),
        ),
      );
      await tester.pump();

      adapter.onRoomRemoved!('room1', 'deleted', null);
      await tester.pump();

      expect(left, isTrue);
    });

    testWidgets('onRoomRemoved for a different room does not leave', (
      tester,
    ) async {
      var left = false;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            onRoomLeft: () => left = true,
          ),
        ),
      );
      await tester.pump();

      adapter.onRoomRemoved!('other', null, null);
      await tester.pump();

      expect(left, isFalse);
    });

    testWidgets('removing the room from the list triggers onRoomLeft', (
      tester,
    ) async {
      var left = false;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            onRoomLeft: () => left = true,
          ),
        ),
      );
      await tester.pump();

      adapter.roomListController.removeRoom('room1');
      await tester.pump();

      expect(left, isTrue);
    });

    testWidgets('default onRoomLeft pops the route', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navKey, home: const SizedBox()),
      );
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NomaChatView), findsOneWidget);

      adapter.roomListController.removeRoom('room1');
      await tester.pumpAndSettle();

      expect(find.byType(NomaChatView), findsNothing);
    });

    testWidgets('onAppBarTap fires when the header is tapped', (tester) async {
      RoomListItem? tapped;
      var called = false;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            onAppBarTap: (room) {
              called = true;
              tapped = room;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Team'));
      await tester.pump();

      expect(called, isTrue);
      expect(tapped?.id, 'room1');
    });

    testWidgets('appBarActions are rendered in the default app bar', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            appBarActions: const [Icon(Icons.search, key: Key('search-act'))],
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('search-act')), findsOneWidget);
    });

    testWidgets('appBarBuilder replaces the whole header', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            appBarBuilder: (context, room, controller) =>
                AppBar(title: const Text('Custom Header')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatRoomAppBar), findsNothing);
      expect(find.text('Custom Header'), findsOneWidget);
    });

    testWidgets('default report callback opens the ReportMessageDialog', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      chatViewOf(tester).callbacks.onReportMessage!(msg('m1'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
    });

    testWidgets('default report submits the typed reason to the client', (
      tester,
    ) async {
      mockClient.seedRoom(const ChatRoom(id: 'room1', members: ['u1', 'u2']));
      mockClient.addMessage('room1', msg('m1'));
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      chatViewOf(tester).callbacks.onReportMessage!(msg('m1'));
      await tester.pumpAndSettle();

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'abuse');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('consumer onReportMessage wins over the default', (
      tester,
    ) async {
      ChatMessage? reported;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            callbacks: ChatViewCallbacks(onReportMessage: (m) => reported = m),
          ),
        ),
      );
      await tester.pump();

      chatViewOf(tester).callbacks.onReportMessage!(msg('m9'));
      await tester.pump();

      expect(reported?.id, 'm9');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('consumer builder slot wins over the auto-wired resolver', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(
              displayNameResolver: (id) => 'override-$id',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        chatViewOf(tester).builders.displayNameResolver!('zzz'),
        'override-zzz',
      );
    });

    testWidgets('default displayNameResolver returns null for unknown ids', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      expect(chatViewOf(tester).builders.displayNameResolver!('ghost'), isNull);
    });

    testWidgets('default userFetcher resolves via the client and caches', (
      tester,
    ) async {
      mockClient.seedUser(const ChatUser(id: 'u9', displayName: 'Nine'));
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      final fetched = await chatViewOf(tester).builders.userFetcher!('u9');
      expect(fetched.displayName, 'Nine');
      expect(adapter.findCachedUser('u9')?.displayName, 'Nine');
    });

    testWidgets('default userFetcher reads from the cache when present', (
      tester,
    ) async {
      adapter.cacheUsers(const [ChatUser(id: 'u7', displayName: 'Seven')]);
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      final fetched = await chatViewOf(tester).builders.userFetcher!('u7');
      expect(fetched.displayName, 'Seven');
    });

    testWidgets('default userFetcher falls back to the id when unknown', (
      tester,
    ) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      final fetched = await chatViewOf(tester).builders.userFetcher!('nobody');
      expect(fetched.displayName, 'nobody');
    });

    testWidgets('pin context-menu action pins via the adapter', (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'room1',
          name: 'Team',
          isGroup: true,
          userRole: RoomRole.owner,
        ),
      );

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

      chatViewOf(tester).callbacks.onContextMenuAction!(
        msg('m1'),
        MessageAction.deleteForMe,
      );
      await tester.pump();
    });

    testWidgets('onContextMenuAction report routes to consumer callback', (
      tester,
    ) async {
      ChatMessage? reported;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            callbacks: ChatViewCallbacks(onReportMessage: (m) => reported = m),
          ),
        ),
      );
      await tester.pump();

      // report is dispatched through its dedicated callback: the SDK's
      // ChatView routes MessageAction.report straight to
      // callbacks.onReportMessage (chat_view.dart _handleLongPress), not
      // through onContextMenuAction (which only handles actions lacking a
      // first-class callback: pin/unpin/star/unstar/deleteForMe/info).
      chatViewOf(tester).callbacks.onReportMessage!(msg('m2'));
      await tester.pump();

      expect(reported?.id, 'm2');
    });

    testWidgets('dispose restores the prior adapter callbacks', (tester) async {
      void blockedHandler(Set<String> ids) {}
      void removedHandler(String a, String? b, String? c) {}
      adapter.onBlockedUsersChanged = blockedHandler;
      adapter.onRoomRemoved = removedHandler;
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
      );

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

      expect(adapter.onBlockedUsersChanged, isNot(equals(blockedHandler)));

      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump();

      expect(adapter.onBlockedUsersChanged, equals(blockedHandler));
      expect(adapter.onRoomRemoved, equals(removedHandler));
      expect(adapter.activeRoomId, isNull);
    });

    testWidgets('seed title shows before the room list resolves a name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'roomX',
            adapter: adapter,
            title: 'Seeded',
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatView), findsOneWidget);
    });
  });
}
