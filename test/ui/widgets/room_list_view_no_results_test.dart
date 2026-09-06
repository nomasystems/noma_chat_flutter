import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late RoomListController controller;

  const rooms = [
    RoomListItem(id: 'a', name: 'Alice'),
    RoomListItem(id: 'b', name: 'Bob'),
    RoomListItem(id: 'c', name: 'Carol'),
  ];

  Widget wrap({bool isLoading = false}) => MaterialApp(
    home: Scaffold(
      body: RoomListView(
        controller: controller,
        isLoading: isLoading,
        showHeader: false,
        showSearch: false,
      ),
    ),
  );

  setUp(() {
    controller = RoomListController()..setRooms(rooms);
  });

  tearDown(() => controller.dispose());

  testWidgets(
    'a filter that matches nothing says "no results", not "no chats"',
    (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.text('Alice'), findsOneWidget);

      controller.setFilter('zzz');
      await tester.pump();

      expect(find.text(ChatUiLocalizations.en.noResults), findsOneWidget);
      expect(find.text(ChatUiLocalizations.en.noChatsYet), findsNothing);
    },
  );

  testWidgets('a filter with no matches waits for the first load to finish', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(isLoading: true));
    controller.setFilter('zzz');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(ChatUiLocalizations.en.noResults), findsNothing);
  });

  testWidgets('a whitespace-only filter counts as a filter', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('Alice'), findsOneWidget);

    controller.setFilter(' ');
    await tester.pump();

    expect(find.text(ChatUiLocalizations.en.noResults), findsOneWidget);
    expect(find.text(ChatUiLocalizations.en.noChatsYet), findsNothing);
  });

  testWidgets('an empty list with no filter still says "no chats yet"', (
    tester,
  ) async {
    controller.setRooms(const []);
    await tester.pumpWidget(wrap());

    expect(find.text(ChatUiLocalizations.en.noChatsYet), findsOneWidget);
    expect(find.text(ChatUiLocalizations.en.noResults), findsNothing);
  });
}
