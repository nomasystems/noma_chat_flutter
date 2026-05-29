import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final l10n = ChatTheme.defaults.l10n;

  const rooms = [
    RoomListItem(id: 'r1', name: 'Alice'),
    RoomListItem(id: 'r2', name: 'Bob'),
    RoomListItem(id: 'r3', name: 'Carol'),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageForwardSheet — rendering', () {
    testWidgets('renders the title and one row per room', (tester) async {
      await tester.pumpWidget(wrap(const MessageForwardSheet(rooms: rooms)));

      expect(find.text(l10n.forwardTo), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
    });

    testWidgets('shows the empty state when there are no rooms', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const MessageForwardSheet(rooms: [])));

      expect(find.text(l10n.noChatsToForward), findsOneWidget);
    });

    testWidgets('renders a custom confirm label', (tester) async {
      await tester.pumpWidget(
        wrap(const MessageForwardSheet(rooms: rooms, confirmLabel: 'Send now')),
      );

      expect(find.text('Send now'), findsOneWidget);
    });

    testWidgets('initialSelectedIds pre-checks the matching row', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageForwardSheet(rooms: rooms, initialSelectedIds: ['r2']),
        ),
      );

      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Bob'),
      );
      expect(tile.value, isTrue);
    });
  });

  group('MessageForwardSheet — selection', () {
    testWidgets('confirm is disabled until something is selected', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const MessageForwardSheet(rooms: rooms)));

      ElevatedButton button() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, l10n.forward),
      );

      expect(button().onPressed, isNull);

      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(button().onPressed, isNotNull);
    });

    testWidgets('maxSelection caps the number of concurrent selections', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MessageForwardSheet(rooms: rooms, maxSelection: 1)),
      );

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Bob'));
      await tester.pump();

      final bob = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Bob'),
      );
      expect(bob.value, isFalse, reason: 'cap of 1 already reached by Alice');
    });

    testWidgets('search filters the visible rows', (tester) async {
      await tester.pumpWidget(
        wrap(const MessageForwardSheet(rooms: rooms, searchEnabled: true)),
      );

      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Carol'), findsNothing);
    });
  });

  group('MessageForwardSheet.show', () {
    Widget launcher(Future<void> Function(BuildContext) onPressed) =>
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => onPressed(context),
                child: const Text('go'),
              ),
            ),
          ),
        );

    testWidgets('empty rooms without onEmpty shows a snackbar, returns null', (
      tester,
    ) async {
      List<String>? result = const ['sentinel'];
      await tester.pumpWidget(
        launcher((context) async {
          result = await MessageForwardSheet.show(
            context: context,
            rooms: const [],
          );
        }),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text(l10n.noChatsToForward), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('empty rooms with onEmpty invokes the callback', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        launcher((context) async {
          await MessageForwardSheet.show(
            context: context,
            rooms: const [],
            onEmpty: (_) => called = true,
          );
        }),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('selecting then confirming returns the chosen ids', (
      tester,
    ) async {
      List<String>? result;
      await tester.pumpWidget(
        launcher((context) async {
          result = await MessageForwardSheet.show(
            context: context,
            rooms: rooms,
          );
        }),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.forward));
      await tester.pumpAndSettle();

      expect(result, ['r1']);
    });
  });
}
