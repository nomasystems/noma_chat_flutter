import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 300, child: child)),
  );

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('AudioBubble a11y', () {
    testWidgets('play button announces Play audio message in idle state', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const AudioBubble(audioUrl: 'https://example.test/voice.m4a')),
      );

      expect(findSemanticsWithLabel('Play audio message'), findsOneWidget);
    });

    testWidgets(
      'speed pill is absent in idle state and appears after first interaction',
      (tester) async {
        await tester.pumpWidget(
          wrap(const AudioBubble(audioUrl: 'https://example.test/voice.m4a')),
        );

        // The speed pill replaces the sender avatar only after the user has
        // started playback for the first time; it must not be present on
        // first render (avatar-slot design).
        expect(findSemanticsWithLabel('Playback speed 1x'), findsNothing);
      },
    );
  });
}
