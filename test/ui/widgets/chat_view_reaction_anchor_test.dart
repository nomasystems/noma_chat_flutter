import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The floating reaction picker is anchored to the row it will react to,
/// measured when it opens rather than when the long press fired: the
/// context menu opens and closes in between, and the list can move under
/// it.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  const pickerHeight = 56.0;
  const margin = 8.0;

  final tintFinder = find.byKey(const ValueKey('chat_active_row_tint'));

  ChatMessage msg(String id, String from, int minute) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: 'message $id',
  );

  List<ChatMessage> history(int count) => [
    for (var i = 0; i < count; i++) msg('m$i', i.isEven ? 'u1' : 'me', i),
  ];

  Finder rowOf(String id, {required bool isOutgoing}) => find.byKey(
    ValueKey(messageBubbleSemanticsId(id, isOutgoing: isOutgoing)),
  );

  Future<ChatController> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
  }) async {
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ChatView(
              controller: controller,
              callbacks: ChatViewCallbacks(
                onSendMessageRequest: (_) => true,
                onReactionSelected: (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Top edge of the emoji row currently on screen.
  double pickerTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(ReactionPicker)).dy;

  testWidgets(
    'the picker anchors to where the row is when it opens, not to where it '
    'was when the long press fired',
    (tester) async {
      final controller = await pumpChat(tester, messages: history(30));

      // React to a message the user can see, exactly as they would.
      final target = rowOf('m28', isOutgoing: false);
      final rectAtLongPress = tester.getRect(target);
      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(find.text('React'), findsOneWidget);

      // The list moves while the context menu is up — a newly arrived
      // message pushes the history, which is what the reversed list does
      // on every incoming message.
      controller.addMessage(msg('m30', 'u1', 30));
      await tester.pumpAndSettle();
      final rectAfterScroll = tester.getRect(target);
      expect(
        rectAfterScroll.top,
        isNot(closeTo(rectAtLongPress.top, 1)),
        reason: 'the row has to actually move for this test to prove anything',
      );

      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();

      expect(find.byType(ReactionPicker), findsOneWidget);
      final top = pickerTop(tester);
      expect(top, closeTo(rectAfterScroll.top - pickerHeight - margin, 1));
      expect(
        top,
        isNot(closeTo(rectAtLongPress.top - pickerHeight - margin, 1)),
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the reacted row stays tinted while the picker is open', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(6));

    final target = rowOf('m4', isOutgoing: false);
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(tintFinder, findsOneWidget);

    await tester.tap(find.text('React'));
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tintFinder,
      findsOneWidget,
      reason: 'the user must keep seeing which message they are reacting to',
    );

    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ReactionPicker), findsNothing);
    expect(tintFinder, findsNothing);
  });

  testWidgets('an unmeasurable row rests the picker over the composer', (
    tester,
  ) async {
    late BuildContext savedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            savedContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    final future = FloatingReactionPicker.show(
      savedContext,
      anchorRect: Rect.zero,
      reactions: const ['👍', '❤️'],
    );
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final top = pickerTop(tester);
    expect(top, closeTo(screenHeight - pickerHeight - margin, 1));

    final picker = tester.getRect(find.byType(ReactionPicker));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(picker.center.dx, closeTo(screenWidth / 2, 1));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('a bubble taller than the viewport keeps the picker on screen', (
    tester,
  ) async {
    late BuildContext savedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            savedContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // A long message whose bubble leaves no room above and ends past the
    // bottom of the screen.
    final future = FloatingReactionPicker.show(
      savedContext,
      anchorRect: Rect.fromLTWH(20, 10, 200, screenHeight - 20),
      reactions: const ['👍', '❤️'],
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(ReactionPicker));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(screenHeight));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });
}
