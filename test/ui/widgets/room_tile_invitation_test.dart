import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('RoomTile invitation', () {
    testWidgets('shows accept and reject buttons for invited room',
        (tester) async {
      final room = RoomListItem(
        id: 'r1',
        name: 'Invited Room',
        custom: const {'invited': true, 'invitedBy': 'u2'},
      );

      await tester.pumpWidget(wrap(RoomTile(room: room)));

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Invited Room'), findsOneWidget);
    });

    testWidgets('accept button triggers onAcceptInvitation', (tester) async {
      var accepted = false;
      final room = RoomListItem(
        id: 'r1',
        name: 'Invited Room',
        custom: const {'invited': true},
      );

      await tester.pumpWidget(wrap(
        RoomTile(
          room: room,
          onAcceptInvitation: () => accepted = true,
        ),
      ));

      await tester.tap(find.text('Accept'));
      expect(accepted, true);
    });

    testWidgets('reject button triggers onRejectInvitation', (tester) async {
      var rejected = false;
      final room = RoomListItem(
        id: 'r1',
        name: 'Invited Room',
        custom: const {'invited': true},
      );

      await tester.pumpWidget(wrap(
        RoomTile(
          room: room,
          onRejectInvitation: () => rejected = true,
        ),
      ));

      await tester.tap(find.text('Reject'));
      expect(rejected, true);
    });

    testWidgets('non-invited room shows last message instead', (tester) async {
      final room = RoomListItem(
        id: 'r1',
        name: 'Normal Room',
        lastMessage: 'Hello',
      );

      await tester.pumpWidget(wrap(RoomTile(room: room)));

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });
  });
}
