import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// On iOS the framework default toolbar for an editable field is
/// [SystemContextMenu], which asserts on every frame once the text input
/// connection is gone while it is still mounted — opening the long-press sheet
/// over the focused composer is enough. The room then paints but answers no
/// gesture at all. Neither the composer nor a bubble may ask for it.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  Future<void> onIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  ChatMessage msg(String id, String from, int minute) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: 'message $id',
  );

  Finder rowOf(String id, {required bool isOutgoing}) => find.byKey(
    ValueKey(messageBubbleSemanticsId(id, isOutgoing: isOutgoing)),
  );

  Future<void> pumpChat(WidgetTester tester) async {
    final controller = ChatController(
      initialMessages: [
        for (var i = 0; i < 6; i++) msg('m$i', i.isEven ? 'u1' : 'me', i),
      ],
      currentUser: me,
      otherUsers: const [alice],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(supportsShowingSystemContextMenu: true),
            child: Scaffold(
              body: SizedBox(
                width: 800,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('long-pressing a text bubble opens the menu without throwing', (
    tester,
  ) async {
    await onIOS(() async {
      await pumpChat(tester);

      await tester.longPress(rowOf('m4', isOutgoing: false));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(SystemContextMenu), findsNothing);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the bubble selection toolbar is rendered by Flutter', (
    tester,
  ) async {
    await onIOS(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(supportsShowingSystemContextMenu: true),
              child: const Scaffold(
                body: TextBubble(text: 'Hello', isOutgoing: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SystemContextMenu), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });

  testWidgets('the composer selection toolbar is rendered by Flutter', (
    tester,
  ) async {
    await onIOS(() async {
      await pumpChat(tester);

      final composer = find.byKey(const ValueKey('chat_message_input'));
      await tester.tap(composer);
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'draft');
      await tester.pumpAndSettle();

      await tester.longPress(composer);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SystemContextMenu), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });
}
