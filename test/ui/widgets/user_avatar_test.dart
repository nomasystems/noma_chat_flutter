import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UserAvatar', () {
    testWidgets('shows initials when no image', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: 'John Doe', size: 40)),
      );
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('shows single initial for single name', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: 'Alice', size: 40)),
      );
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows ? when no name', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(size: 40)));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('shows ? for whitespace-only name', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: '   ', size: 40)),
      );
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('handles name with multiple spaces between words', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: 'John   Doe', size: 40)),
      );
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('shows online indicator when isOnline true', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: 'Test', size: 40, isOnline: true)),
      );
      final containers = find.byType(Container);
      expect(containers, findsWidgets);
    });

    testWidgets('no indicator when isOnline null', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(displayName: 'Test', size: 40)),
      );
      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.isOnline, isNull);
      expect(find.byType(SizedBox), findsNothing);
    });
  });
}
