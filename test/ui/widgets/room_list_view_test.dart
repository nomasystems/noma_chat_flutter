import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListView', () {
    testWidgets('shows loading indicator when isLoading and empty', (
      tester,
    ) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              isLoading: true,
              showHeader: false,
              showSearch: false,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('shows empty state when not loading and empty', (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              isLoading: false,
              showHeader: false,
              showSearch: false,
            ),
          ),
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('uses emptyBuilder instead of default EmptyState', (
      tester,
    ) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              isLoading: false,
              showHeader: false,
              showSearch: false,
              emptyBuilder: (_) => const Text('Custom empty'),
            ),
          ),
        ),
      );

      expect(find.text('Custom empty'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('renders rooms from the controller', (tester) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
      controller.addRoom(const RoomListItem(id: 'r2', name: 'Beta'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
            ),
          ),
        ),
      );

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('onTapRoom is invoked with the tapped room', (tester) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
      RoomListItem? tapped;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
              onTapRoom: (room) => tapped = room,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(tapped?.id, 'r1');
    });

    testWidgets('renders the search bar when showSearch is true', (
      tester,
    ) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(controller: controller, showHeader: false),
          ),
        ),
      );

      expect(find.byType(RoomSearchBar), findsOneWidget);
    });

    testWidgets('renders the header when showHeader is true', (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showSearch: false,
              headerTitle: 'My chats',
            ),
          ),
        ),
      );

      expect(find.text('My chats'), findsOneWidget);
    });

    testWidgets('rebuilds when controller notifies new rooms', (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
            ),
          ),
        ),
      );
      expect(find.byType(EmptyState), findsOneWidget);

      controller.addRoom(const RoomListItem(id: 'r1', name: 'Late arrival'));
      await tester.pumpAndSettle();

      expect(find.text('Late arrival'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('selectedRoomId highlights the matching tile', (tester) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
      controller.addRoom(const RoomListItem(id: 'r2', name: 'Beta'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
              selectedRoomId: 'r2',
            ),
          ),
        ),
      );

      final alphaTile = tester.widget<RoomTile>(
        find.ancestor(of: find.text('Alpha'), matching: find.byType(RoomTile)),
      );
      final betaTile = tester.widget<RoomTile>(
        find.ancestor(of: find.text('Beta'), matching: find.byType(RoomTile)),
      );
      expect(alphaTile.isSelected, isFalse);
      expect(betaTile.isSelected, isTrue);
    });

    testWidgets('selectedRoomId does not affect tiles when null (default)', (
      tester,
    ) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
            ),
          ),
        ),
      );

      final alphaTile = tester.widget<RoomTile>(
        find.ancestor(of: find.text('Alpha'), matching: find.byType(RoomTile)),
      );
      expect(alphaTile.isSelected, isFalse);
    });

    testWidgets(
      'onSelectionChanged fires alongside onTapRoom outside multi-select',
      (tester) async {
        final controller = RoomListController();
        controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
        RoomListItem? tapped;
        RoomListItem? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoomListView(
                controller: controller,
                showHeader: false,
                showSearch: false,
                onTapRoom: (room) => tapped = room,
                onSelectionChanged: (room) => selected = room,
              ),
            ),
          ),
        );

        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();

        expect(tapped?.id, 'r1');
        expect(selected?.id, 'r1');
      },
    );

    testWidgets('onSelectionChanged does not fire during multi-select mode', (
      tester,
    ) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
      controller.addRoom(const RoomListItem(id: 'r2', name: 'Beta'));
      controller.toggleSelect('r2');
      var selectionChangedCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
              onSelectionChanged: (_) => selectionChangedCalls++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(selectionChangedCalls, 0);
      expect(controller.selectedIds, {'r1', 'r2'});
    });

    testWidgets('statusIconBuilder is forwarded to every RoomTile', (
      tester,
    ) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
              statusIconBuilder: (context, data) => const Text('tick'),
            ),
          ),
        ),
      );

      final alphaTile = tester.widget<RoomTile>(
        find.ancestor(of: find.text('Alpha'), matching: find.byType(RoomTile)),
      );
      expect(alphaTile.statusIconBuilder, isNotNull);
    });
  });

  group('RoomListView long press', () {
    Future<void> pumpList(
      WidgetTester tester, {
      void Function(RoomListItem, RoomAction)? onContextMenuAction,
      ValueChanged<RoomListItem>? onLongPressRoom,
    }) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomListView(
              controller: controller,
              showHeader: false,
              showSearch: false,
              onContextMenuAction: onContextMenuAction,
              onLongPressRoom: onLongPressRoom,
            ),
          ),
        ),
      );
    }

    Iterable<InkWell> tileInkWells(WidgetTester tester) =>
        tester.widgetList<InkWell>(
          find.descendant(
            of: find.byType(RoomTile),
            matching: find.byType(InkWell),
          ),
        );

    testWidgets('opens no menu when nothing can answer the actions', (
      tester,
    ) async {
      await pumpList(tester);

      expect(tileInkWells(tester), isNotEmpty);
      expect(tileInkWells(tester).every((w) => w.onLongPress == null), isTrue);

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.byType(RoomContextMenu), findsNothing);
    });

    testWidgets('opens the default menu and routes the picked action', (
      tester,
    ) async {
      RoomAction? picked;
      String? pickedRoomId;

      await pumpList(
        tester,
        onContextMenuAction: (room, action) {
          picked = action;
          pickedRoomId = room.id;
        },
      );

      expect(tileInkWells(tester).any((w) => w.onLongPress != null), isTrue);

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomContextMenu), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(picked, RoomAction.delete);
      expect(pickedRoomId, 'r1');
    });

    testWidgets('onLongPressRoom alone keeps the gesture wired', (
      tester,
    ) async {
      RoomListItem? pressed;

      await pumpList(tester, onLongPressRoom: (room) => pressed = room);

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(pressed?.id, 'r1');
      expect(find.byType(RoomContextMenu), findsNothing);
    });
  });
}
