import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

const _rawId = '11111111-2222-3333-4444-555555555555';

/// What the forward picker narrows by. Without a host resolver it is the
/// same rule the room list applies — resolved title *and* raw server name,
/// never an identifier. With one it is the host's own text, so the row is
/// found by what its reader can see.
void main() {
  const rooms = [
    RoomListItem(
      id: 'r1',
      name: 'Weekend trip',
      effectiveDisplayName: 'Escapada',
      isGroup: true,
    ),
    RoomListItem(id: 'r2', name: 'Bob'),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> searchIn(WidgetTester tester, Widget sheet, String query) async {
    await tester.pumpWidget(wrap(sheet));
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }

  Future<void> search(WidgetTester tester, String query) => searchIn(
    tester,
    const MessageForwardSheet(rooms: rooms, searchEnabled: true),
    query,
  );

  group('default rule', () {
    testWidgets('the raw server name still finds a renamed room', (
      tester,
    ) async {
      await search(tester, 'weekend');

      expect(find.text('Escapada'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('the resolved title finds it too', (tester) async {
      await search(tester, 'escap');

      expect(find.text('Escapada'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('a query matching neither name shows nothing', (tester) async {
      await search(tester, 'zzz');

      expect(find.text('Escapada'), findsNothing);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('a name that is the room id never finds its own room', (
      tester,
    ) async {
      await searchIn(
        tester,
        const MessageForwardSheet(
          rooms: [RoomListItem(id: 'room-42', name: 'room-42')],
          searchEnabled: true,
        ),
        'room-4',
      );

      expect(find.text('room-42'), findsNothing);
    });

    testWidgets('a name seeded with the peer id is not searchable', (
      tester,
    ) async {
      const seeded = MessageForwardSheet(
        rooms: [
          RoomListItem(
            id: 'r3',
            name: _rawId,
            otherUserId: _rawId,
            effectiveDisplayName: 'Pepe',
          ),
        ],
        searchEnabled: true,
      );
      await searchIn(tester, seeded, _rawId.substring(0, 8));

      expect(find.text('Pepe'), findsNothing);

      await searchIn(tester, seeded, 'pep');

      expect(find.text('Pepe'), findsOneWidget);
    });
  });

  group('searchTextResolver', () {
    const titles = {'r1': 'Chat with Pepe', 'r2': 'Plan: Sunday barbecue'};

    Widget sheet() => MessageForwardSheet(
      rooms: rooms,
      searchEnabled: true,
      rowBuilder: (context, room, isSelected, onToggle) =>
          Text(titles[room.id]!),
      searchTextResolver: (context, room) => titles[room.id]!,
    );

    testWidgets('the painted title finds the row', (tester) async {
      await searchIn(tester, sheet(), 'pepe');

      expect(find.text('Chat with Pepe'), findsOneWidget);
      expect(find.text('Plan: Sunday barbecue'), findsNothing);
    });

    testWidgets('the raw display name no longer finds it', (tester) async {
      await searchIn(tester, sheet(), 'escapada');

      expect(find.text('Chat with Pepe'), findsNothing);
      expect(find.text('Plan: Sunday barbecue'), findsNothing);
    });

    testWidgets('the raw server name no longer finds it either', (
      tester,
    ) async {
      await searchIn(tester, sheet(), 'weekend');

      expect(find.text('Chat with Pepe'), findsNothing);
      expect(find.text('Plan: Sunday barbecue'), findsNothing);
    });

    testWidgets('a second row is found by its own resolved title', (
      tester,
    ) async {
      await searchIn(tester, sheet(), 'barbecue');

      expect(find.text('Plan: Sunday barbecue'), findsOneWidget);
      expect(find.text('Chat with Pepe'), findsNothing);
    });
  });
}
