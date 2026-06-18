import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('shows the "@" badge when unreadMentions > 0', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RoomTile(
          room: RoomListItem(
            id: 'r1',
            name: 'Team',
            unreadCount: 3,
            unreadMentions: 1,
          ),
        ),
      ),
    );
    expect(find.text('@'), findsOneWidget);
  });

  testWidgets('hides the "@" badge when unreadMentions == 0', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RoomTile(
          room: RoomListItem(id: 'r1', name: 'Team', unreadCount: 3),
        ),
      ),
    );
    expect(find.text('@'), findsNothing);
  });
}
