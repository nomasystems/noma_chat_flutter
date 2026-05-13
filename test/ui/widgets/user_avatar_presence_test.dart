import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UserAvatar presenceStatus', () {
    testWidgets('shows green dot for available', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.available,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.green;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('shows amber dot for away', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.away,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.amber;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('shows red dot for busy', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.busy,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.red;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('shows deep red dot for dnd', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.dnd,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.red.shade900;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('shows grey dot for offline', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.offline,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.grey;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('presenceStatus takes priority over isOnline', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        isOnline: true,
        presenceStatus: PresenceStatus.away,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.amber;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('falls back to isOnline when no presenceStatus', (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        isOnline: true,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.green;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('no dot when both isOnline and presenceStatus null',
        (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
      )));

      expect(find.byType(SizedBox), findsNothing);
    });

    testWidgets('uses custom theme presence colors', (tester) async {
      const customColor = Color(0xFF123456);
      const theme = ChatTheme(presenceAwayColor: customColor);

      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.away,
        theme: theme,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == customColor;
      });
      expect(containers, isNotEmpty);
    });

    testWidgets('shows dot when only presenceStatus provided (no isOnline)',
        (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(
        displayName: 'Test',
        size: 40,
        presenceStatus: PresenceStatus.busy,
      )));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) {
        final d = c.decoration as BoxDecoration;
        return d.shape == BoxShape.circle && d.color == Colors.red;
      });
      expect(containers, isNotEmpty);
    });
  });
}
