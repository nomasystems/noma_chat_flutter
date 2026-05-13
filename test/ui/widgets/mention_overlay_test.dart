import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final users = [
    ChatUser(id: 'u1', displayName: 'Alice Smith'),
    ChatUser(id: 'u2', displayName: 'Bob Jones'),
    ChatUser(id: 'u3', displayName: 'Charlie Brown'),
  ];

  group('MentionOverlay', () {
    testWidgets('filters users by query', (tester) async {
      await tester.pumpWidget(
        wrap(
          MentionOverlay(
            query: 'ali',
            users: users,
            onSelect: (_) {},
          ),
        ),
      );
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsNothing);
      expect(find.text('Charlie Brown'), findsNothing);
    });

    testWidgets('calls onSelect when user tapped', (tester) async {
      ChatUser? selected;
      await tester.pumpWidget(
        wrap(
          MentionOverlay(
            query: '',
            users: users,
            onSelect: (u) => selected = u,
          ),
        ),
      );

      await tester.tap(find.text('Bob Jones'));
      expect(selected?.id, 'u2');
    });

    testWidgets('shows empty when no match', (tester) async {
      await tester.pumpWidget(
        wrap(
          MentionOverlay(
            query: 'zzz',
            users: users,
            onSelect: (_) {},
          ),
        ),
      );
      expect(find.byType(Card), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
