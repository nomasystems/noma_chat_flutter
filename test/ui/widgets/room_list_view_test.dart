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

    testWidgets('shows empty state when not loading and empty', (
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

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RoomListView(
            controller: controller,
            showHeader: false,
            showSearch: false,
          ),
        ),
      ));

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('onTapRoom is invoked with the tapped room', (tester) async {
      final controller = RoomListController();
      controller.addRoom(const RoomListItem(id: 'r1', name: 'Alpha'));
      RoomListItem? tapped;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RoomListView(
            controller: controller,
            showHeader: false,
            showSearch: false,
            onTapRoom: (room) => tapped = room,
          ),
        ),
      ));

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(tapped?.id, 'r1');
    });

    testWidgets('renders the search bar when showSearch is true',
        (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RoomListView(
            controller: controller,
            showHeader: false,
          ),
        ),
      ));

      expect(find.byType(RoomSearchBar), findsOneWidget);
    });

    testWidgets('renders the header when showHeader is true', (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RoomListView(
            controller: controller,
            showSearch: false,
            headerTitle: 'My chats',
          ),
        ),
      ));

      expect(find.text('My chats'), findsOneWidget);
    });

    testWidgets('rebuilds when controller notifies new rooms', (tester) async {
      final controller = RoomListController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RoomListView(
            controller: controller,
            showHeader: false,
            showSearch: false,
          ),
        ),
      ));
      expect(find.byType(EmptyState), findsOneWidget);

      controller.addRoom(const RoomListItem(id: 'r1', name: 'Late arrival'));
      await tester.pumpAndSettle();

      expect(find.text('Late arrival'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });
  });
}
