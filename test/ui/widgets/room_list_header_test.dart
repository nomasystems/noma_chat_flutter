import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RoomListHeader', () {
    testWidgets('shows title when not selecting', (tester) async {
      await tester.pumpWidget(wrap(
        const RoomListHeader(title: 'Messages'),
      ));

      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('shows selected count when selecting', (tester) async {
      await tester.pumpWidget(wrap(
        const RoomListHeader(
          isSelecting: true,
          selectedCount: 3,
        ),
      ));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('cancel button has 48x48 touch target', (tester) async {
      await tester.pumpWidget(wrap(
        RoomListHeader(
          isSelecting: true,
          selectedCount: 1,
          onCancelSelection: () {},
        ),
      ));

      final sizedBox = tester.widget<SizedBox>(find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.width == 48 &&
            widget.height == 48,
      ));
      expect(sizedBox.width, 48);
      expect(sizedBox.height, 48);
    });
  });
}
