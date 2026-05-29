import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('RoomTile a11y', () {
    testWidgets('exposes room display name as semantic label', (tester) async {
      final room = fixtureRoomListItem(name: 'Team Chat');

      await tester.pumpWidget(wrap(RoomTile(room: room)));

      expect(findSemanticsWithLabel('Team Chat'), findsOneWidget);
    });

    testWidgets('hides the raw room id behind an empty fallback label', (
      tester,
    ) async {
      const room = RoomListItem(id: 'room-internal-uuid');

      await tester.pumpWidget(wrap(const RoomTile(room: room)));

      expect(findSemanticsWithLabel('room-internal-uuid'), findsNothing);
    });

    testWidgets(
      'room with unread count exposes both name and unread badge label',
      (tester) async {
        final room = fixtureRoomListItem(name: 'Family', unreadCount: 4);

        await tester.pumpWidget(wrap(RoomTile(room: room)));

        expect(findSemanticsWithLabel('Family'), findsOneWidget);
        expect(findSemanticsWithLabel('4 unread'), findsOneWidget);
      },
    );
  });
}
