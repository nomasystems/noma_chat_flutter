import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const l10n = ChatUiLocalizations.en;

  StarredMessage star(String id, String room) => StarredMessage(
    userId: 'me',
    messageId: id,
    roomId: room,
    starredAt: DateTime.utc(2026, 6, 15, 10),
  );

  testWidgets('renders one row per starred message via roomTitleFor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StarredMessagesView(
            load: () async => [star('m1', 'r1'), star('m2', 'r2')],
            roomTitleFor: (roomId) => 'Room $roomId',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room r1'), findsOneWidget);
    expect(find.text('Room r2'), findsOneWidget);
  });

  testWidgets('unstar removes the row optimistically and reports it', (
    tester,
  ) async {
    StarredMessage? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StarredMessagesView(
            load: () async => [star('m1', 'r1')],
            roomTitleFor: (roomId) => 'Room $roomId',
            onUnstar: (s) async => removed = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room r1'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.unstar));
    await tester.pumpAndSettle();
    // Unstar now goes through a WhatsApp-style confirmation dialog
    // (StarredMessagesView._confirmUnstar). Confirm it to drop the row.
    expect(find.text(l10n.unstarConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unstar));
    await tester.pumpAndSettle();
    expect(removed?.messageId, 'm1');
    expect(find.text('Room r1'), findsNothing);
  });

  testWidgets('shows the empty state when nothing is starred', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StarredMessagesView(load: () async => const [])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.noStarredMessages), findsOneWidget);
  });
}
