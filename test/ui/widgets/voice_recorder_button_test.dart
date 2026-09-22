import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('VoiceRecorderButton', () {
    testWidgets('renders microphone icon', (tester) async {
      await tester.pumpWidget(wrap(const VoiceRecorderButton()));
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('has semantics label', (tester) async {
      await tester.pumpWidget(wrap(const VoiceRecorderButton()));
      expect(find.bySemanticsLabel('Record voice message'), findsOneWidget);
    });

    for (final scale in const [1.18, 1.18 * 1.7]) {
      testWidgets('answers touches on a 44pt square while painting a 40pt '
          'circle (text scale $scale)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: SizedBox(
                  width: 375,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: VoiceRecorderButton(),
                  ),
                ),
              ),
            ),
          ),
        );

        final target = tester.getSize(find.byType(VoiceRecorderButton));
        expect(target.width, greaterThanOrEqualTo(44));
        expect(target.height, greaterThanOrEqualTo(44));

        final circle = tester.getSize(
          find
              .descendant(
                of: find.byType(VoiceRecorderButton),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(circle, const Size(40, 40));
      });
    }

    testWidgets('voiceIconBuilder takes precedence over voiceButtonIcon', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const VoiceRecorderButton(
            theme: ChatTheme(
              input: ChatInputTheme(voiceIconBuilder: _customMic),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('custom-mic')), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    });
  });
}

Widget _customMic(BuildContext context) =>
    const Icon(Icons.graphic_eq, key: Key('custom-mic'));
