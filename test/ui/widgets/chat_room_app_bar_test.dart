import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

ChatController _controller({
  List<ChatUser> otherUsers = const [],
  Set<String> typingUserIds = const {},
}) {
  final c = ChatController(
    initialMessages: const [],
    currentUser: const ChatUser(id: 'me', displayName: 'Me'),
    otherUsers: otherUsers,
  );
  for (final u in typingUserIds) {
    c.setTyping(u, true);
  }
  return c;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(appBar: child as PreferredSizeWidget, body: const SizedBox()),
);

void main() {
  group('ChatRoomAppBar', () {
    testWidgets('renders the room display name', (tester) async {
      final c = _controller();
      const room = RoomListItem(id: 'r1', name: 'Team');
      await tester.pumpWidget(_wrap(ChatRoomAppBar(controller: c, room: room)));
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets(
      'falls back to an empty title when room has no displayable name '
      '(never expose UUIDs)',
      (tester) async {
        final c = _controller();
        const room = RoomListItem(id: 'r1');
        await tester.pumpWidget(
          _wrap(ChatRoomAppBar(controller: c, room: room)),
        );
        // The room id 'r1' must NOT surface anywhere — neither as title
        // nor as semantic label.
        expect(find.text('r1'), findsNothing);
      },
    );

    testWidgets('shows online subtitle for 1:1 rooms when peer is online', (
      tester,
    ) async {
      final c = _controller();
      const room = RoomListItem(id: 'r1', name: 'Alice', isOnline: true);
      await tester.pumpWidget(_wrap(ChatRoomAppBar(controller: c, room: room)));
      expect(find.text('online'), findsOneWidget);
    });

    testWidgets(
      'shows "last seen …" subtitle for 1:1 rooms when peer is offline '
      'with a known lastSeen',
      (tester) async {
        final c = _controller();
        final room = RoomListItem(
          id: 'r1',
          name: 'Alice',
          isOnline: false,
          lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await tester.pumpWidget(
          _wrap(ChatRoomAppBar(controller: c, room: room)),
        );
        expect(find.textContaining('last seen'), findsOneWidget);
      },
    );

    testWidgets(
      'shows no subtitle for 1:1 rooms when peer is offline with no known '
      'lastSeen',
      (tester) async {
        final c = _controller();
        const room = RoomListItem(id: 'r1', name: 'Alice', isOnline: false);
        await tester.pumpWidget(
          _wrap(ChatRoomAppBar(controller: c, room: room)),
        );
        expect(find.text('online'), findsNothing);
        expect(find.textContaining('last seen'), findsNothing);
      },
    );

    testWidgets('shows typing subtitle when peers are typing', (tester) async {
      final c = _controller(
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
        typingUserIds: const {'u1'},
      );
      const room = RoomListItem(id: 'r1', name: 'Alice');
      await tester.pumpWidget(_wrap(ChatRoomAppBar(controller: c, room: room)));
      // typingOneTemplate = '{name} is typing'
      expect(find.text('Alice is typing'), findsOneWidget);
      // Cancel the typing timeout timer the controller scheduled at
      // setTyping(true); otherwise the binding asserts on a pending
      // Timer when the test ends.
      c.setTyping('u1', false);
      c.dispose();
    });

    testWidgets('shows member count for groups when no one is typing', (
      tester,
    ) async {
      final c = _controller();
      const room = RoomListItem(
        id: 'r1',
        name: 'Team',
        isGroup: true,
        memberCount: 5,
      );
      await tester.pumpWidget(_wrap(ChatRoomAppBar(controller: c, room: room)));
      expect(find.text('5 members'), findsOneWidget);
    });

    testWidgets('avatarBuilder overrides the default UserAvatar', (
      tester,
    ) async {
      final c = _controller();
      const room = RoomListItem(id: 'r1', name: 'Alice');
      await tester.pumpWidget(
        _wrap(
          ChatRoomAppBar(
            controller: c,
            room: room,
            avatarBuilder: (_) =>
                const SizedBox(key: ValueKey('custom-avatar')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('custom-avatar')), findsOneWidget);
    });

    testWidgets('subtitleBuilder receives the resolved subtitle string', (
      tester,
    ) async {
      final c = _controller();
      const room = RoomListItem(id: 'r1', name: 'Alice', isOnline: true);
      String? received;
      await tester.pumpWidget(
        _wrap(
          ChatRoomAppBar(
            controller: c,
            room: room,
            subtitleBuilder: (context, subtitle) {
              received = subtitle;
              return null;
            },
          ),
        ),
      );
      expect(received, 'online');
    });
  });
}
