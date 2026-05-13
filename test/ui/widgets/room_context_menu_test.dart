import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RoomContextMenu', () {
    testWidgets('shows mute for unmuted room', (tester) async {
      final room = RoomListItem(id: 'r1', muted: false, unreadCount: 1);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Unmute'), findsNothing);
    });

    testWidgets('shows unmute for muted room', (tester) async {
      final room = RoomListItem(id: 'r1', muted: true);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Mute'), findsNothing);
    });

    testWidgets('shows pin for unpinned room', (tester) async {
      final room = RoomListItem(id: 'r1', pinned: false);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Pin'), findsOneWidget);
    });

    testWidgets('shows unpin for pinned room', (tester) async {
      final room = RoomListItem(id: 'r1', pinned: true);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Unpin'), findsOneWidget);
    });

    testWidgets('shows mark as read when unread', (tester) async {
      final room = RoomListItem(id: 'r1', unreadCount: 5);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Mark as read'), findsOneWidget);
    });

    testWidgets('hides mark as read when no unread', (tester) async {
      final room = RoomListItem(id: 'r1', unreadCount: 0);
      await tester.pumpWidget(wrap(RoomContextMenu(room: room)));
      expect(find.text('Mark as read'), findsNothing);
    });

    testWidgets('calls onAction', (tester) async {
      RoomAction? received;
      final room = RoomListItem(id: 'r1');
      await tester.pumpWidget(
        wrap(RoomContextMenu(room: room, onAction: (a) => received = a)),
      );
      await tester.tap(find.text('Delete'));
      expect(received, RoomAction.delete);
    });
  });
}
