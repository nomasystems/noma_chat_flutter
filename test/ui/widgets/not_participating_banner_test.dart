import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final l10n = ChatTheme.defaults.l10n;

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('NotParticipatingBanner', () {
    testWidgets('renders the default localized banner copy', (tester) async {
      await tester.pumpWidget(wrap(const NotParticipatingBanner()));

      expect(find.text(l10n.notParticipatingBanner), findsOneWidget);
    });

    testWidgets('renders a custom label override', (tester) async {
      await tester.pumpWidget(
        wrap(const NotParticipatingBanner(label: 'Custom copy')),
      );

      expect(find.text('Custom copy'), findsOneWidget);
      expect(find.text(l10n.notParticipatingBanner), findsNothing);
    });
  });
}
