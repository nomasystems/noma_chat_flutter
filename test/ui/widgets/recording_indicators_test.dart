import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart' show ChatTheme;
// ignore: implementation_imports — `_recording_indicators` is intentionally
// kept out of the public barrel; the test imports it by path to cover it.
import 'package:noma_chat/src/ui/widgets/_recording_indicators.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('LockHintPill', () {
    testWidgets('renders the lock and animated up-arrow icons', (tester) async {
      await tester.pumpWidget(
        wrap(const LockHintPill(theme: ChatTheme.defaults)),
      );
      // Drive a few frames of the looping animation (pumpAndSettle would
      // never return — the controller repeats forever).
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));

      // Still mounted and rendering after several animation ticks.
      expect(find.byType(LockHintPill), findsOneWidget);
    });
  });
}
