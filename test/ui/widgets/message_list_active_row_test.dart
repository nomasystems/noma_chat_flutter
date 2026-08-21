import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The "chosen row" tint: while the context menu opened from a long press
/// is up, the whole row is tinted; it goes back to its own colour as soon
/// as the menu closes.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  final tintFinder = find.byKey(const ValueKey('chat_active_row_tint'));
  final incomingRow = find.byKey(
    ValueKey(messageBubbleSemanticsId('m1', isOutgoing: false)),
  );

  ChatMessage msg(String id, String from) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10),
    text: 'msg $id',
  );

  Future<ChatController> pumpList(
    WidgetTester tester, {
    required bool opensMenu,
    bool highlight = true,
  }) async {
    final controller = ChatController(
      initialMessages: [msg('m1', 'u1'), msg('m2', 'me')],
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: Builder(
              builder: (context) => MessageList(
                controller: controller,
                highlightRowWhileContextMenuOpen: highlight,
                onMessageLongPress: (message, rect) {
                  if (!opensMenu) return;
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) =>
                        const SizedBox(height: 120, child: Text('menu')),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('the row stays tinted while its menu is open and clears after', (
    tester,
  ) async {
    await pumpList(tester, opensMenu: true);

    expect(tintFinder, findsNothing);

    await tester.longPress(incomingRow);
    await tester.pumpAndSettle();

    expect(find.text('menu'), findsOneWidget);
    expect(tintFinder, findsOneWidget);
    final tinted = tester.widget<Container>(tintFinder);
    expect(tinted.color, isNotNull);

    // Closing the menu returns the row to its own colour.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('menu'), findsNothing);
    expect(tintFinder, findsNothing);
  });

  testWidgets('a long press that opens nothing leaves no tint behind', (
    tester,
  ) async {
    await pumpList(tester, opensMenu: false);

    await tester.longPress(incomingRow);
    await tester.pump();

    // Tinted on press — the list cannot know yet that nothing will open.
    expect(tintFinder, findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tintFinder, findsNothing);
  });

  testWidgets('highlightRowWhileContextMenuOpen: false opts out entirely', (
    tester,
  ) async {
    await pumpList(tester, opensMenu: true, highlight: false);

    await tester.longPress(incomingRow);
    await tester.pumpAndSettle();

    expect(find.text('menu'), findsOneWidget);
    expect(tintFinder, findsNothing);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('activeRowMessageId drives the tint without any long press', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: [msg('m1', 'u1')],
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: MessageList(
              controller: controller,
              activeRowMessageId: 'm1',
              activeRowColor: const Color(0xFF00FF00),
            ),
          ),
        ),
      ),
    );

    expect(tintFinder, findsOneWidget);
    expect(tester.widget<Container>(tintFinder).color, const Color(0xFF00FF00));
  });
}
