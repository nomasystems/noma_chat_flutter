import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('paints the matched participant under the room name', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const RoomTile(
          room: RoomListItem(
            id: 'group-1',
            name: 'Weekend trip',
            lastMessage: 'see you there',
            isGroup: true,
          ),
          matchedParticipant: 'Alice',
        ),
      ),
    );

    expect(find.text('Weekend trip'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    final style = tester.widget<Text>(find.text('Alice')).style;
    expect(style?.fontStyle, FontStyle.italic);
  });

  testWidgets('paints nothing extra without a matched participant', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const RoomTile(
          room: RoomListItem(
            id: 'group-1',
            name: 'Weekend trip',
            lastMessage: 'see you there',
            isGroup: true,
          ),
        ),
      ),
    );

    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('an empty matched participant paints no line', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RoomTile(
          room: RoomListItem(id: 'group-1', name: 'Weekend trip'),
          matchedParticipant: '',
        ),
      ),
    );

    expect(find.text(''), findsNothing);
  });

  testWidgets('RoomListView wires the match from the controller', (
    tester,
  ) async {
    final controller = RoomListController(
      initialRooms: const [
        RoomListItem(
          id: 'group-1',
          name: 'Weekend trip',
          lastMessage: 'see you there',
          isGroup: true,
        ),
      ],
      participantNameResolver: (room) => const ['Alice', 'Bob'],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(SizedBox(height: 400, child: RoomListView(controller: controller))),
    );

    expect(find.text('Alice'), findsNothing);

    controller.setFilter('ali');
    await tester.pump();

    expect(find.text('Weekend trip'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });
}
