import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// U88 — the long-press sheet used to lift the whole conversation by its own
/// height plus 72, whatever the bubble needed. A bubble that was not already
/// at the bottom of the list went off the TOP of the screen: the sheet
/// stopped covering it by taking it away.
///
/// The lift is now measured against the bubble — enough to clear the sheet,
/// never past the `safeTop + 72` the quick-reaction row needs above it, and
/// nothing at all when the bubble already sits clear.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  /// What the old code added at the bottom of the list, unconditionally.
  double oldFixedLift(Rect sheet) => sheet.height + 72;

  ChatMessage msg(String id, String from, int minute) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: 'message $id',
  );

  Finder rowOf(String id, {required bool isOutgoing}) => find.byKey(
    ValueKey(messageBubbleSemanticsId(id, isOutgoing: isOutgoing)),
  );

  Future<void> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    double width = 800,
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
            width: width,
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
  }

  Future<void> pumpHistory(WidgetTester tester) => pumpChat(
    tester,
    messages: [
      for (var i = 0; i < 30; i++) msg('m$i', i.isEven ? 'u1' : 'me', i),
    ],
  );

  Rect sheetOf(WidgetTester tester) => tester.getRect(find.byType(BottomSheet));

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  }

  testWidgets('a bubble the sheet never reaches is not moved at all', (
    tester,
  ) async {
    await pumpHistory(tester);

    final target = rowOf('m22', isOutgoing: false);
    final before = tester.getRect(target);

    await tester.longPress(target);
    await tester.pumpAndSettle();

    final sheet = sheetOf(tester);
    final after = tester.getRect(target);

    expect(
      before.bottom,
      lessThan(sheet.top),
      reason: 'setup: this bubble starts clear of the sheet',
    );
    expect(
      after.top,
      closeTo(before.top, 0.5),
      reason: 'nothing to get out of the way of, so nothing moves',
    );
    expect(
      before.top - oldFixedLift(sheet),
      lessThan(0),
      reason: 'the old fixed lift would have pushed it off the top',
    );

    await dismiss(tester);
  });

  testWidgets('a covered bubble rises exactly as much as the sheet covers', (
    tester,
  ) async {
    await pumpHistory(tester);

    final target = rowOf('m28', isOutgoing: false);
    final before = tester.getRect(target);

    await tester.longPress(target);
    await tester.pumpAndSettle();

    final sheet = sheetOf(tester);
    final after = tester.getRect(target);
    final lift = before.top - after.top;

    expect(
      before.bottom,
      greaterThan(sheet.top),
      reason: 'setup: this bubble really is under the sheet',
    );
    expect(after.bottom, lessThanOrEqualTo(sheet.top + 0.5));
    expect(lift, greaterThan(0));
    expect(
      lift,
      lessThan(oldFixedLift(sheet)),
      reason: 'the whole complaint: it used to rise far more than it needed',
    );
    expect(
      after.top,
      greaterThanOrEqualTo(72.0),
      reason: 'the quick-reaction row has to fit above it',
    );

    expect(find.byType(ReactionPicker), findsOneWidget);
    final picker = tester.getRect(find.byType(ReactionPicker));
    expect(picker.top, greaterThanOrEqualTo(0));
    expect(picker.bottom, lessThanOrEqualTo(after.top + 0.5));

    await dismiss(tester);
  });

  testWidgets('a bubble too tall for the band keeps its place on screen', (
    tester,
  ) async {
    // 466pt tall in a 600pt viewport: it cannot both clear the sheet and
    // leave the row its 72 above. Staying put beats leaving the screen.
    await pumpChat(
      tester,
      width: 300,
      messages: [
        ChatMessage(
          id: 'tall',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1, 10),
          text: 'word ' * 62,
        ),
      ],
    );

    final target = rowOf('tall', isOutgoing: false);
    final before = tester.getRect(target);

    await tester.longPress(target);
    await tester.pumpAndSettle();

    final sheet = sheetOf(tester);
    final after = tester.getRect(target);

    expect(
      before.top,
      lessThan(72.0),
      reason: 'setup: there is no room above it for the row',
    );
    expect(after.top, closeTo(before.top, 0.5));
    expect(after.top, greaterThanOrEqualTo(0));
    expect(
      before.top - oldFixedLift(sheet),
      lessThan(0),
      reason: 'the old fixed lift took this bubble off the screen entirely',
    );

    await dismiss(tester);
  });
}
