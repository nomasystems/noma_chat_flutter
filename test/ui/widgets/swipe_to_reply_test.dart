import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/widgets/swipe_to_reply.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SwipeToReply', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(
        wrap(SwipeToReply(onSwipe: () {}, child: const Text('Message'))),
      );
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets(
      'triggers onSwipe callback after horizontal drag past threshold',
      (tester) async {
        var swiped = false;
        await tester.pumpWidget(
          wrap(
            SwipeToReply(
              onSwipe: () => swiped = true,
              child: const SizedBox(width: 200, height: 50, child: Text('Msg')),
            ),
          ),
        );

        await tester.drag(find.text('Msg'), const Offset(65, 0));
        await tester.pumpAndSettle();

        expect(swiped, isTrue);
      },
    );
  });
}
