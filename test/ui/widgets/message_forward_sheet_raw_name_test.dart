import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The forward picker narrows the same way the room list does: a group a
/// host [RoomTitleResolver] renamed stays reachable by the name the server
/// still carries, and by the resolved one.
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

  Future<void> search(WidgetTester tester, String query) async {
    await tester.pumpWidget(
      wrap(const MessageForwardSheet(rooms: rooms, searchEnabled: true)),
    );
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }

  testWidgets('the raw server name still finds a renamed room', (tester) async {
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
}
