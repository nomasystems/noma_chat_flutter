import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListController — archived partition', () {
    test('rooms excludes hidden, archivedRooms returns only hidden', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', name: 'Active'),
          RoomListItem(id: 'b', name: 'Archived', hidden: true),
        ],
      );
      expect(controller.rooms.map((r) => r.id), ['a']);
      expect(controller.archivedRooms.map((r) => r.id), ['b']);
      expect(controller.hasArchivedRooms, isTrue);
    });

    test('archivedRooms honours the active text filter', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', name: 'Alpha', hidden: true),
          RoomListItem(id: 'b', name: 'Beta', hidden: true),
        ],
      )..setFilter('alph');
      expect(controller.archivedRooms.map((r) => r.id), ['a']);
    });

    test('hasArchivedRooms is false with no hidden rooms', () {
      final controller = RoomListController(
        initialRooms: const [RoomListItem(id: 'a', name: 'A')],
      );
      expect(controller.hasArchivedRooms, isFalse);
    });
  });

  group('RoomListView — Archived section', () {
    testWidgets('renders a collapsible Archived header that reveals rooms', (
      tester,
    ) async {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', name: 'Active'),
          RoomListItem(id: 'b', name: 'ArchivedRoom', hidden: true),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RoomListView(controller: controller)),
        ),
      );

      // Header present, active room visible, archived row hidden until expand.
      expect(find.textContaining('Archived'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('ArchivedRoom'), findsNothing);

      await tester.tap(find.textContaining('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('ArchivedRoom'), findsOneWidget);
    });
  });
}
