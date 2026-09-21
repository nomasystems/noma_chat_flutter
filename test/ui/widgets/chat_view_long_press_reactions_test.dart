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

  /// A host that wired [ChatViewCallbacks.onReactionSelected] and nothing
  /// else, which is all [ChatView] has ever asked for.
  Future<List<String>> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    Map<String, Set<String>> userReactions = const {},
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
              behaviors: ChatViewBehaviors(userReactions: userReactions),
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

  /// A host menu whose height follows the keyboard, as WB's does: the
  /// sheet's route keeps rebuilding through its exit animation, so a
  /// height that changes then re-measures a session already over.
  Future<void> pumpChatWithElasticMenu(
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
              callbacks: ChatViewCallbacks(onSendMessageRequest: (_) => true),
              builders: ChatViewBuilders(
                contextMenuBuilder: (sheetContext, message, isOutgoing) =>
                    SizedBox(
                      height: MediaQuery.viewInsetsOf(sheetContext).bottom > 0
                          ? 140
                          : 200,
                      child: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(
                            sheetContext,
                          ).pop(MessageAction.copy),
                          child: const Text('Close'),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Same chat, but the screen can be taken out of the tree without
  /// tearing down the root overlay the row lives in, and the emoji the
  /// user has already reacted with can be seeded.
  Future<
    ({List<String> reacted, List<String> deleted, VoidCallback removeScreen})
  >
  pumpDetachableChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    Map<String, Set<String>> userReactions = const {},
  }) async {
    final reacted = <String>[];
    final deleted = <String>[];
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    late StateSetter setScreenState;
    var attached = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setScreenState = setState;
              if (!attached) return const SizedBox.shrink();
              return SizedBox(
                height: 600,
                child: ChatView(
                  controller: controller,
                  behaviors: ChatViewBehaviors(userReactions: userReactions),
                  callbacks: ChatViewCallbacks(
                    onSendMessageRequest: (_) => true,
                    onReactionSelected: (message, emoji) =>
                        reacted.add('${message.id}:$emoji'),
                    onDeleteReaction: (message, emoji) =>
                        deleted.add('${message.id}:$emoji'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      reacted: reacted,
      deleted: deleted,
      removeScreen: () => setScreenState(() => attached = false),
    );
  }

  /// Same chat under a [GlobalKey], moved between two slots of the same
  /// [Row]. Reparenting is the one way out of a subtree that never calls
  /// `dispose`: the element is deactivated and adopted again, so only
  /// `deactivate` stands between the row and the screen it belongs to.
  Future<VoidCallback> pumpReparentableChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
  }) async {
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    final chatKey = GlobalKey();
    late StateSetter setScreenState;
    var inFirstSlot = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setScreenState = setState;
              final chat = SizedBox(
                height: 500,
                child: ChatView(
                  key: chatKey,
                  controller: controller,
                  callbacks: ChatViewCallbacks(
                    onSendMessageRequest: (_) => true,
                  ),
                ),
              );
              return Row(
                children: [
                  SizedBox(width: 400, child: inFirstSlot ? chat : null),
                  SizedBox(width: 400, child: inFirstSlot ? null : chat),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => setScreenState(() => inFirstSlot = false);
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

  testWidgets('picking an action from the sheet closes the row as well', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();
    expect(find.byType(ReactionPicker), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsNothing);
  });

  testWidgets(
    'the keyboard moving as the sheet leaves does not bring it back',
    (tester) async {
      await pumpChatWithElasticMenu(tester, messages: history(10));

      await tester.longPress(rowOf('m8', isOutgoing: false));
      await tester.pumpAndSettle();
      expect(find.byType(ReactionPicker), findsOneWidget);

      addTearDown(tester.view.reset);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(find.byType(ReactionPicker), findsNothing);
    },
  );

  testWidgets('the "+" does not leave the row behind the full picker', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat_reaction_picker_more')));
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsNothing);
  });

  testWidgets('taking the screen out of the tree takes the row with it', (
    tester,
  ) async {
    final session = await pumpDetachableChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();
    expect(find.byType(ReactionPicker), findsOneWidget);

    session.removeScreen();
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsNothing);
  });

  testWidgets('moving the screen to another parent takes the row with it', (
    tester,
  ) async {
    final reparent = await pumpReparentableChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();
    expect(find.byType(ReactionPicker), findsOneWidget);

    reparent();
    await tester.pumpAndSettle();

    expect(find.byType(ReactionPicker), findsNothing);
  });

  testWidgets('a route arriving before the row is placed keeps it away', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(10));

    await tester.longPress(rowOf('m8', isOutgoing: false));
    Navigator.of(
      tester.element(find.byType(ChatView)),
      rootNavigator: true,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('on top')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('on top'), findsOneWidget);
    expect(find.byType(ReactionPicker), findsNothing);
  });

  testWidgets('tapping the emoji I already reacted with takes it back', (
    tester,
  ) async {
    final session = await pumpDetachableChat(
      tester,
      messages: history(10),
      userReactions: const {
        'm8': {'\u{1F44D}'},
      },
    );

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('\u{1F44D}'));
    await tester.pumpAndSettle();

    expect(session.deleted, ['m8:\u{1F44D}']);
    expect(session.reacted, isEmpty);
  });

  testWidgets('with no delete callback the pick is still a reaction', (
    tester,
  ) async {
    final reacted = await pumpChat(
      tester,
      messages: history(10),
      userReactions: const {
        'm8': {'\u{1F44D}'},
      },
    );

    await tester.longPress(rowOf('m8', isOutgoing: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('\u{1F44D}').first);
    await tester.pumpAndSettle();

    expect(reacted, ['m8:\u{1F44D}']);
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
