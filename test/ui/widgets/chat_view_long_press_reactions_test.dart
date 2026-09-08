import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// U88 — reacting used to cost three gestures: long press, "React", emoji.
/// The row now comes up WITH the action sheet, "React" leaves the sheet
/// because the row's own "+" already opens the full picker, and the sheet
/// stops covering the message it is acting on.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  ChatMessage msg(
    String id,
    String from,
    int minute, {
    bool isDeleted = false,
  }) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: isDeleted ? '' : 'message $id',
    isDeleted: isDeleted,
  );

  List<ChatMessage> history(int count) => [
    for (var i = 0; i < count; i++) msg('m$i', i.isEven ? 'u1' : 'me', i),
  ];

  Finder rowOf(String id, {required bool isOutgoing}) => find.byKey(
    ValueKey(messageBubbleSemanticsId(id, isOutgoing: isOutgoing)),
  );

  Future<List<String>> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
  }) async {
    final reacted = <String>[];
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
                onReactionSelected: (message, emoji) =>
                    reacted.add('${message.id}:$emoji'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return reacted;
  }

  testWidgets('one long press brings up the emoji row AND the action sheet', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('"React" is gone from the sheet: the row\'s "+" is that door', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    expect(find.text('React'), findsNothing);
    expect(
      find.byKey(const ValueKey('chat_reaction_picker_more')),
      findsOneWidget,
    );
  });

  testWidgets('the sheet does not cover the message it is acting on', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(30));

    final target = rowOf('m29', isOutgoing: true);
    await tester.longPress(target);
    await tester.pumpAndSettle();

    final bubble = tester.getRect(target);
    final sheet = tester.getRect(find.byType(BottomSheet));
    final row = tester.getRect(find.byType(ReactionPicker));

    expect(
      bubble.bottom,
      lessThanOrEqualTo(sheet.top),
      reason: 'the whole point: you can see what you are acting on',
    );
    expect(row.bottom, lessThanOrEqualTo(bubble.top + 1));
    expect(row.top, greaterThanOrEqualTo(0));
  });

  testWidgets('tapping an emoji reacts and closes BOTH', (tester) async {
    final reacted = await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('\u{1F44D}'));
    await tester.pumpAndSettle();

    expect(reacted, ['m8:\u{1F44D}']);
    expect(find.byType(ReactionPicker), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Reply'), findsNothing);
  });

  testWidgets('dismissing the sheet puts the conversation back where it was', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(30));

    final target = rowOf('m29', isOutgoing: true);
    final before = tester.getRect(target);

    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(tester.getRect(target).top, isNot(closeTo(before.top, 1)));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsNothing);
    expect(tester.getRect(target).top, closeTo(before.top, 1));
  });

  testWidgets(
    'a tombstone gets the sheet with no emoji row: nothing to react to',
    (tester) async {
      await pumpChat(
        tester,
        messages: [...history(6), msg('gone', 'u1', 7, isDeleted: true)],
      );

      await tester.longPress(rowOf('gone', isOutgoing: false));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ReactionPicker), findsNothing);
    },
  );
}
