import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ForwardedBubble', () {
    testWidgets('shows default Forwarded label', (tester) async {
      await tester.pumpWidget(
        wrap(const ForwardedBubble(child: Text('content'))),
      );
      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
      expect(find.byIcon(Icons.forward), findsOneWidget);
    });

    testWidgets('shows custom source label', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ForwardedBubble(
            sourceLabel: 'From #general',
            child: Text('content'),
          ),
        ),
      );
      expect(find.text('From #general'), findsOneWidget);
    });

    testWidgets('appends the source timestamp when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          ForwardedBubble(
            sourceLabel: 'From #general',
            sourceTimestamp: DateTime(2025, 3, 12, 9),
            child: const Text('content'),
          ),
        ),
      );
      expect(find.text('From #general · 12/03/2025'), findsOneWidget);
    });

    testWidgets('omits the timestamp suffix when sourceTimestamp is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ForwardedBubble(
            sourceLabel: 'From #general',
            child: Text('content'),
          ),
        ),
      );
      expect(find.text('From #general'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets(
      'appends the timestamp to the default label when sourceLabel is null',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ForwardedBubble(
              sourceTimestamp: DateTime(2025, 3, 12, 9),
              child: const Text('content'),
            ),
          ),
        );
        expect(find.text('Forwarded · 12/03/2025'), findsOneWidget);
      },
    );
  });
}
