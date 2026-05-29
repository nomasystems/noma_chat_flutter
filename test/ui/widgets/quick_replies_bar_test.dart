import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('QuickRepliesBar', () {
    testWidgets('renders one chip per reply label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          QuickRepliesBar(
            replies: const ['Yes', 'No', 'Maybe'],
            onReply: (_) {},
          ),
        ),
      );
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Maybe'), findsOneWidget);
    });

    testWidgets('empty replies list collapses to zero size', (tester) async {
      await tester.pumpWidget(
        _wrap(QuickRepliesBar(replies: const [], onReply: (_) {})),
      );
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('tap dispatches the tapped label', (tester) async {
      String? lastTapped;
      await tester.pumpWidget(
        _wrap(
          QuickRepliesBar(
            replies: const ['Confirm'],
            onReply: (label) => lastTapped = label,
          ),
        ),
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(lastTapped, 'Confirm');
    });
  });
}
