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

    testWidgets('voiceIconBuilder takes precedence over voiceButtonIcon',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const VoiceRecorderButton(
            theme: ChatTheme(voiceIconBuilder: _customMic),
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
