import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// D79 — sending with the list scrolled up left the view where it was, so you
/// never saw your own message; and the floating "back to the bottom" button
/// could not appear at all in a room whose whole history is shorter than the
/// fixed 200 px threshold.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const other = ChatUser(id: 'u2', displayName: 'Bob');

  ChatMessage msg(
    String id, {
    String from = 'u2',
    String text = 'msg',
    DateTime? ts,
  }) => ChatMessage(
    id: id,
    from: from,
    text: text,
    timestamp: ts ?? DateTime(2026, 1, 1, 12),
  );

  Widget wrap(ChatController controller) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 500,
        width: 400,
        child: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => MessageList(controller: controller),
        ),
      ),
    ),
  );

  ChatController longHistory() => ChatController(
    initialMessages: List<ChatMessage>.generate(
      40,
      (i) => msg('m$i', text: 'message number $i', ts: DateTime(2026, 1, 1, i)),
    ),
    currentUser: me,
  );

  group('auto-scroll on own message', () {
    testWidgets(
      'sending from halfway up the history snaps back to the bottom',
      (tester) async {
        final controller = longHistory();
        controller.setOtherUsers([other]);
        await tester.pumpWidget(wrap(controller));
        await tester.pump();

        final sc = controller.scrollController;
        sc.jumpTo(300);
        await tester.pump();
        expect(sc.offset, 300);

        controller.addMessage(
          msg(
            'mine',
            from: 'u1',
            text: 'sent from up here',
            ts: DateTime(2026, 1, 5),
          ),
        );
        await tester.pumpAndSettle();

        expect(sc.offset, 0);
        controller.dispose();
      },
    );

    testWidgets('an incoming message does not steal the viewport', (
      tester,
    ) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      final sc = controller.scrollController;
      sc.jumpTo(300);
      await tester.pump();

      controller.addMessage(
        msg('theirs', text: 'from Bob', ts: DateTime(2026, 1, 5)),
      );
      await tester.pumpAndSettle();

      expect(sc.offset, isNot(0));
      controller.dispose();
    });

    testWidgets('loading older history does not move the list, not even when '
        'the older page is mine', (tester) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      final sc = controller.scrollController;
      sc.jumpTo(300);
      await tester.pump();

      controller.addMessages([
        for (var i = 0; i < 5; i++)
          msg(
            'old$i',
            from: 'u1',
            text: 'older $i',
            ts: DateTime(2025, 12, 31, i),
          ),
      ]);
      await tester.pumpAndSettle();

      expect(sc.offset, 300);
      controller.dispose();
    });

    testWidgets('opening a room does not scroll on its own', (tester) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(wrap(controller));
      await tester.pumpAndSettle();

      expect(controller.scrollController.offset, 0);
      controller.dispose();
    });
  });

  group('scroll-to-bottom button threshold', () {
    test('a short room whose whole history fits under 200 px can still show '
        'the button', () {
      // The reported room: 192 px of scrollable extent, end to end.
      expect(MessageListState.isScrolledUp(192, 192), isTrue);
      expect(MessageListState.isScrolledUp(60, 192), isTrue);
    });

    test('a barely-scrolled list does not flash the button', () {
      expect(MessageListState.isScrolledUp(10, 192), isFalse);
      expect(MessageListState.isScrolledUp(0, 192), isFalse);
      expect(MessageListState.isScrolledUp(47, 5000), isFalse);
    });

    test('the fixed threshold still governs a long history', () {
      expect(MessageListState.isScrolledUp(201, 5000), isTrue);
      expect(MessageListState.isScrolledUp(150, 5000), isFalse);
    });

    testWidgets('the button appears once the list is scrolled up', (
      tester,
    ) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsNothing);

      controller.scrollController.jumpTo(300);
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      controller.dispose();
    });
  });

  group('unread badge on the button', () {
    testWidgets('the pill the button has always accepted is finally wired', (
      tester,
    ) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              width: 400,
              child: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => MessageList(
                  controller: controller,
                  unreadCount: 4,
                  unreadBoundaryMessageId: 'm38',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      controller.scrollController.jumpTo(300);
      await tester.pump();

      final button = tester.widget<ScrollToBottomButton>(
        find.byType(ScrollToBottomButton),
      );
      expect(button.unreadCount, 4);
      expect(find.byType(UnreadBadge), findsOneWidget);
      controller.dispose();
    });

    testWidgets('no boundary snapshot means no pill', (tester) async {
      final controller = longHistory();
      controller.setOtherUsers([other]);
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      controller.scrollController.jumpTo(300);
      await tester.pump();

      final button = tester.widget<ScrollToBottomButton>(
        find.byType(ScrollToBottomButton),
      );
      expect(button.unreadCount, 0);
      controller.dispose();
    });
  });
}
