import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const l10n = ChatUiLocalizations.en;

  group('MuteDuration', () {
    test('until() computes the right expiry per choice', () {
      final now = DateTime.utc(2026, 6, 15, 10);
      expect(
        MuteDuration.eightHours.until(now),
        now.add(const Duration(hours: 8)),
      );
      expect(MuteDuration.oneWeek.until(now), now.add(const Duration(days: 7)));
      expect(MuteDuration.always.until(now), isNull);
    });

    test('label() resolves localized strings', () {
      expect(MuteDuration.eightHours.label(l10n), l10n.mute8Hours);
      expect(MuteDuration.oneWeek.label(l10n), l10n.mute1Week);
      expect(MuteDuration.always.label(l10n), l10n.muteAlways);
    });
  });

  group('MuteDurationSheet', () {
    testWidgets('lists the three options and returns the chosen one', (
      tester,
    ) async {
      MuteDuration? chosen;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  opened = true;
                  chosen = await MuteDurationSheet.show(context, l10n: l10n);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(find.text(l10n.mute8Hours), findsOneWidget);
      expect(find.text(l10n.mute1Week), findsOneWidget);
      expect(find.text(l10n.muteAlways), findsOneWidget);

      await tester.tap(find.text(l10n.mute1Week));
      await tester.pumpAndSettle();
      expect(chosen, MuteDuration.oneWeek);
    });
  });
}
