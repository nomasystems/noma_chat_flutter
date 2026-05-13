import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('EmptyState', () {
    testWidgets('renders all elements', (tester) async {
      await tester.pumpWidget(
        wrap(
          EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No messages',
            subtitle: 'Start a conversation',
            action: ElevatedButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      );
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.text('No messages'), findsOneWidget);
      expect(find.text('Start a conversation'), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
    });

    testWidgets('renders with only title', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(title: 'Empty')));
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('renders empty when no props', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState()));
      expect(find.byType(EmptyState), findsOneWidget);
    });
  });
}
