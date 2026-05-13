import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('FloatingReactionPicker', () {
    testWidgets('shows predefined emojis near anchor', (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              savedContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final future = FloatingReactionPicker.show(
        savedContext,
        anchorRect: const Rect.fromLTWH(100, 300, 200, 50),
        reactions: ['👍', '❤️'],
      );

      await tester.pumpAndSettle();

      expect(find.text('👍'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);

      // Dismiss by tapping barrier
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(await future, isNull);
    });

    testWidgets('returns selected emoji on tap', (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              savedContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final future = FloatingReactionPicker.show(
        savedContext,
        anchorRect: const Rect.fromLTWH(100, 300, 200, 50),
        reactions: ['👍', '❤️'],
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();

      expect(await future, '👍');
    });

    testWidgets('dismiss on barrier tap returns null', (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              savedContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final future = FloatingReactionPicker.show(
        savedContext,
        anchorRect: const Rect.fromLTWH(100, 300, 200, 50),
        reactions: ['👍'],
      );

      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(await future, isNull);
    });
  });
}
