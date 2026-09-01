import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The quick-reaction row is anchored to the message it will react to,
/// measured when it opens rather than when the long press fired: the sheet
/// lifts the conversation out from under itself in between, so the row has
/// moved by the time the emoji have somewhere to sit.
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

  /// A bubble tall enough that the row cannot simply sit above it.
  ChatMessage tallMsg(String id, int lines) => ChatMessage(
    id: id,
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 11),
    text: [for (var i = 0; i < lines; i++) 'line $i'].join('\n'),
  );

  Finder rowOf(String id, {required bool isOutgoing}) => find.byKey(
    ValueKey(messageBubbleSemanticsId(id, isOutgoing: isOutgoing)),
  );

  Future<ChatController> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    bool withAppBar = false,
    void Function(ChatMessage, String)? onReaction,
    Widget Function(BuildContext, ChatMessage, bool)? contextMenuBuilder,
  }) async {
    final controller = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    final view = ChatView(
      controller: controller,
      builders: ChatViewBuilders(contextMenuBuilder: contextMenuBuilder),
      callbacks: ChatViewCallbacks(
        onSendMessageRequest: (_) => true,
        onReactionSelected: onReaction ?? (_, __) {},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: withAppBar
            ? Scaffold(
                appBar: AppBar(title: const Text('Alice')),
                body: view,
              )
            : Scaffold(body: SizedBox(height: 600, child: view)),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Top edge of the emoji row currently on screen.
  double pickerTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(ReactionPicker)).dy;

  Rect pickerRect(WidgetTester tester) =>
      tester.getRect(find.byType(ReactionPicker));

  Finder emojiButton(String emoji) =>
      find.byKey(ValueKey('chat_reaction_picker_$emoji'));

  testWidgets(
    'the row anchors to where the message sits once the sheet has lifted the '
    'list, not to where it was when the long press fired',
    (tester) async {
      await pumpChat(tester, messages: history(30));

      final target = rowOf('m28', isOutgoing: false);
      final rectAtLongPress = tester.getRect(target);

      await tester.longPress(target);
      await tester.pumpAndSettle();

      // Opening the sheet reserves room at the bottom of the list, which
      // moves the message up and out from under it.
      final rectUnderSheet = tester.getRect(target);
      expect(
        rectUnderSheet.top,
        isNot(closeTo(rectAtLongPress.top, 1)),
        reason: 'the row has to actually move for this test to prove anything',
      );

      expect(find.byType(ReactionPicker), findsOneWidget);
      final top = pickerTop(tester);
      expect(top, closeTo(rectUnderSheet.top - pickerHeight - margin, 1));
      expect(
        top,
        isNot(closeTo(rectAtLongPress.top - pickerHeight - margin, 1)),
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a bubble tall enough to eat the viewport still leaves the row under the '
    'status bar, and every emoji in it takes a tap',
    (tester) async {
      // The window has a status bar and the view sits in a Scaffold with an
      // app bar, which is where the row used to be measured from: the body's
      // MediaQuery has that inset taken out of it already, so the row went to
      // the top of the WINDOW, where the platform eats every tap.
      tester.view.padding = const FakeViewPadding(top: 59 * 3);
      addTearDown(tester.view.reset);

      const safeTop = 59.0;
      final picked = <String>[];
      await pumpChat(
        tester,
        messages: [...history(6), tallMsg('tall', 16)],
        withAppBar: true,
        onReaction: (_, emoji) => picked.add(emoji),
      );

      final target = rowOf('tall', isOutgoing: false);
      expect(
        tester.getRect(target).height,
        greaterThan(300),
        reason: 'the bubble has to be tall enough to force the row upwards',
      );

      await tester.longPress(target);
      await tester.pumpAndSettle();

      final row = pickerRect(tester);
      expect(row.top, greaterThanOrEqualTo(safeTop + margin));
      // Under the status bar is not enough: the lift is worked out from the
      // room above the bubble, and reading that from the body's MediaQuery
      // instead of the window's overstates it by exactly the status bar,
      // which lifts the bubble behind the app bar rather than up to it.
      expect(
        tester.getRect(target).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
        reason: 'the message being reacted to has to stay readable as well',
      );

      for (final emoji in const ['👍', '❤️', '😂']) {
        expect(
          emojiButton(emoji).hitTestable(),
          findsOneWidget,
          reason: '$emoji has to be reachable, not just visible',
        );
      }

      await tester.tap(emojiButton('😂'));
      await tester.pumpAndSettle();
      expect(picked, ['😂']);
    },
  );

  testWidgets(
    'a bubble sitting too high to be lifted still keeps the row below the '
    'status bar rather than under it',
    (tester) async {
      // Nothing lifts this bubble: there is no room above it, so the reserve
      // is zero and the row is placed straight over the rect. Its natural top
      // lands inside the status bar, and the only thing holding the row out of
      // there is the clamp reading the WINDOW's padding — the body's own
      // MediaQuery has the status bar taken out of it already and clamps to
      // nothing.
      tester.view.padding = const FakeViewPadding(top: 59 * 3);
      addTearDown(tester.view.reset);

      const safeTop = 59.0;
      await pumpChat(tester, messages: history(30), withAppBar: true);

      final target = rowOf('m21', isOutgoing: true);
      final rectAtLongPress = tester.getRect(target);
      expect(
        rectAtLongPress.top - pickerHeight - margin,
        lessThan(safeTop + margin),
        reason:
            'the row must want to go into the status bar, or the clamp '
            'this test is about never gets a say',
      );

      await tester.longPress(target);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(target).top,
        closeTo(rectAtLongPress.top, 1),
        reason:
            'a bubble with no headroom is not lifted, so the row is placed '
            'exactly where the clamp leaves it',
      );
      expect(pickerRect(tester).top, greaterThanOrEqualTo(safeTop + margin));

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the row stays clear of the open menu when the list settles underneath '
    'after the lift was measured',
    (tester) async {
      // The keyboard closing as the sheet opens drops the conversation back
      // down, past the sheet's own top edge, after the lift meant to keep it
      // clear was worked out against the rect it had before. A sheet that
      // re-measures then places the row again, over a bubble that is no
      // longer where the lift left it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.reset);

      const menuKey = ValueKey('host_menu');
      await pumpChat(
        tester,
        messages: history(30),
        contextMenuBuilder: (ctx, _, __) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom > 0 ? 40 : 0,
          ),
          child: const SizedBox(
            key: menuKey,
            height: 240,
            child: Center(child: Text('Reply')),
          ),
        ),
      );

      final target = rowOf('m28', isOutgoing: false);
      final rectAtLongPress = tester.getRect(target);
      await tester.longPress(target);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byKey(menuKey));
      expect(
        tester.getRect(target).top,
        isNot(closeTo(rectAtLongPress.top, 1)),
        reason: 'the list has to move underneath for this to prove anything',
      );
      expect(
        tester.getRect(target).bottom,
        lessThanOrEqualTo(menu.top + 0.01),
        reason: 'the message being acted on cannot be left behind the sheet',
      );
      expect(
        pickerRect(tester).bottom,
        lessThanOrEqualTo(menu.top + 0.01),
        reason: 'the row must never cover an action of the menu it opens with',
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the row and the bubble follow the conversation when the keyboard closes '
    'under a sheet whose own height never changes',
    (tester) async {
      // The SDK's own menu is a fixed height: it is measured once and never
      // reports again. The keyboard closing as the sheet opens drops the
      // whole conversation afterwards, so nothing tied to the sheet can
      // notice — the bubble ends up behind the sheet and the row hangs over
      // whatever message took its place.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.reset);

      await pumpChat(tester, messages: history(30));

      final target = rowOf('m28', isOutgoing: false);
      final rectAtLongPress = tester.getRect(target);
      await tester.longPress(target);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(MessageContextMenu));
      final bubble = tester.getRect(target);
      expect(
        bubble.top,
        isNot(closeTo(rectAtLongPress.top, 1)),
        reason: 'the list has to move underneath for this to prove anything',
      );
      expect(
        bubble.bottom,
        lessThanOrEqualTo(menu.top + 0.01),
        reason: 'the message being acted on cannot be left behind the sheet',
      );
      expect(
        pickerRect(tester).bottom,
        closeTo(bubble.top - margin, 1),
        reason: 'the row has to stay on the message it will react to',
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the row and the bubble follow a keyboard that goes in a single frame '
    'with the sheet already at rest',
    (tester) async {
      // A resize that lands in one go with the sheet at rest leaves the
      // reserve already worked out, so nothing changes state and nothing
      // schedules the frame the re-measure rides on: the bubble is left
      // behind the sheet and the row over whatever took its place. An IME
      // with no animation, a rotation and a split view all resize like this.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.reset);

      await pumpChat(tester, messages: history(30));

      final target = rowOf('m28', isOutgoing: false);
      await tester.longPress(target);
      await tester.pumpAndSettle();
      final rectUnderSheet = tester.getRect(target);
      expect(
        find.byType(ReactionPicker),
        findsOneWidget,
        reason:
            'the sheet has to have finished settling before the keyboard '
            'goes, or this is the same case as the test above it',
      );

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(MessageContextMenu));
      final bubble = tester.getRect(target);
      expect(
        bubble.top,
        isNot(closeTo(rectUnderSheet.top, 1)),
        reason: 'the list has to move underneath for this to prove anything',
      );
      expect(
        bubble.bottom,
        lessThanOrEqualTo(menu.top + 0.01),
        reason: 'the message being acted on cannot be left behind the sheet',
      );
      expect(
        pickerRect(tester).bottom,
        closeTo(bubble.top - margin, 1),
        reason: 'the row has to stay on the message it will react to',
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the reacted row stays tinted while the emoji row is open', (
    tester,
  ) async {
    await pumpChat(tester, messages: history(6));

    final target = rowOf('m4', isOutgoing: false);
    await tester.longPress(target);
    await tester.pumpAndSettle();

    expect(tintFinder, findsOneWidget);
    expect(find.byType(ReactionPicker), findsOneWidget);

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tintFinder,
      findsOneWidget,
      reason: 'the user must keep seeing which message they are reacting to',
    );

    await tester.tap(find.text('\u{1F44D}'));
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
