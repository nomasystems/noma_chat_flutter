import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/fixtures.dart';

/// The selection gesture spans the whole row, and does so without adding a
/// second stop to the accessibility tree.
///
/// Both halves matter and they pull against each other: the area is bought
/// with a `GestureDetector` around the row, and a `GestureDetector` publishes
/// a semantics node carrying a `longPress` action unless told not to. On iOS
/// an action alone makes a node focusable, so the careless version of this
/// feature hands VoiceOver a full-width, label-less stop stacked over the
/// bubble's own. The second group is what fails if that flag is dropped.
void main() {
  Finder findBubble(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400, child: child),
      ),
    ),
  );

  group('MessageBubble long-press area', () {
    testWidgets('fires from the empty side of the row, not just the bubble', (
      tester,
    ) async {
      var longPressed = 0;
      final message = fixtureMessage(text: 'hi', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () => longPressed++,
          ),
        ),
      );

      final row = tester.getRect(find.byType(MessageBubble));
      final bubble = tester.getRect(findBubble('Bob: hi, 12:00'));
      // A point on the row's own line, past the right edge of an incoming
      // bubble — dead space before this change.
      final outside = Offset(row.right - 4, bubble.center.dy);
      expect(outside.dx, greaterThan(bubble.right));

      await tester.longPressAt(outside);
      await tester.pump();

      expect(longPressed, 1);
    });

    // Inside the bubble but off the glyphs: the text itself is selectable
    // and its own long-press recognizer wins that arena — it did before this
    // change too, so the padding is what "the bubble" means for this gesture.
    testWidgets('still fires from inside the bubble', (tester) async {
      var longPressed = 0;
      final message = fixtureMessage(text: 'hi', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () => longPressed++,
          ),
        ),
      );

      final bubble = tester.getRect(findBubble('Bob: hi, 12:00'));
      await tester.longPressAt(bubble.bottomLeft + const Offset(3, -3));
      await tester.pump();

      // Exactly one recognizer wins the arena: the row's. A nested second
      // detector on the bubble would still report 1 here, but the count
      // guards against a future "fix" that forwards the callback twice.
      expect(longPressed, 1);
    });

    // The swipe-to-reply drag wraps the bubble column and is now a
    // descendant of the row detector: the two share an arena. A drag must
    // still beat a stationary press.
    testWidgets('does not swallow the swipe-to-reply drag', (tester) async {
      var longPressed = 0;
      var swiped = 0;
      final message = fixtureMessage(text: 'hi', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () => longPressed++,
            onSwipeToReply: () => swiped++,
          ),
        ),
      );

      await tester.drag(findBubble('Bob: hi, 12:00'), const Offset(90, 0));
      await tester.pumpAndSettle();

      expect(swiped, 1);
      expect(longPressed, 0);
    });
  });

  group('MessageBubble long-press semantics', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('the row detector publishes no node of its own', (
      tester,
    ) async {
      final message = fixtureMessage(text: 'hola', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () {},
          ),
        ),
      );

      // One node offers the action — the bubble's, the one that carries the
      // label. The row's detector is `excludeFromSemantics: true` precisely
      // so this stays one.
      expect(find.semantics.byAction(SemanticsAction.longPress), findsOne);
      expect(
        find.semantics.byAction(SemanticsAction.longPress),
        isSemantics(label: 'Bob: hola, 12:00'),
      );
    });

    testWidgets('the screen-reader action still reaches the callback', (
      tester,
    ) async {
      var longPressed = false;
      final message = fixtureMessage(text: 'hola', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () => longPressed = true,
          ),
        ),
      );

      tester.semantics.performAction(
        find.semantics.byLabel('Bob: hola, 12:00'),
        SemanticsAction.longPress,
      );

      expect(longPressed, isTrue);
    });
  });
}
