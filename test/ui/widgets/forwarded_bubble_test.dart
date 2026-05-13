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
  });
}
