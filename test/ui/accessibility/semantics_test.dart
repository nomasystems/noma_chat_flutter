import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  Finder findSemanticsWithLabel(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );
  }

  group('Accessibility - Semantic labels', () {
    testWidgets('ScrollToBottomButton has scroll to bottom semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollToBottomButton(visible: true, onPressed: () {}),
          ),
        ),
      );

      expect(findSemanticsWithLabel('Scroll to bottom'), findsOneWidget);
    });

    testWidgets('RoomTile has room name as semantic label', (tester) async {
      const room = RoomListItem(id: 'r1', name: 'Team Chat');

      await tester.pumpWidget(wrap(const RoomTile(room: room)));
      expect(findSemanticsWithLabel('Team Chat'), findsOneWidget);
    });

    testWidgets(
      'RoomTile uses empty string as semantic label when name is null '
      '(never expose UUIDs as titles)',
      (tester) async {
        const room = RoomListItem(id: 'room-xyz');

        await tester.pumpWidget(wrap(const RoomTile(room: room)));
        // The room id must not surface — the fallback chain ends at
        // `''` for both rendering and accessibility.
        expect(findSemanticsWithLabel('room-xyz'), findsNothing);
        expect(findSemanticsWithLabel(''), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('UnreadBadge has unread messages semantics', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 7)));
      expect(findSemanticsWithLabel('7 unread'), findsOneWidget);
    });

    testWidgets('UnreadBadge label reflects count', (tester) async {
      await tester.pumpWidget(wrap(const UnreadBadge(count: 42)));
      expect(findSemanticsWithLabel('42 unread'), findsOneWidget);
    });

    testWidgets('VoiceRecorderButton has record voice semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VoiceRecorderButton())),
      );

      expect(findSemanticsWithLabel('Record voice message'), findsOneWidget);
    });

    testWidgets('MessageInput send button has send semantics', (tester) async {
      final controller = ChatController(
        initialMessages: [],
        currentUser: const ChatUser(id: 'u1', displayName: 'Alice'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageInput(
              controller: controller,
              onSendMessageRequest: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      expect(findSemanticsWithLabel('Send'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('ReplyPreview close button has close semantics', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'm1',
        from: 'alice',
        timestamp: DateTime(2026, 1, 1),
        text: 'hi',
      );
      await tester.pumpWidget(
        wrap(ReplyPreview(message: msg, onDismiss: () {})),
      );
      expect(findSemanticsWithLabel('Close'), findsOneWidget);
    });

    testWidgets('PinnedMessagesBanner close button has close semantics', (
      tester,
    ) async {
      final pin = MessagePin(
        roomId: 'r1',
        messageId: 'm1',
        pinnedBy: 'alice',
        pinnedAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          PinnedMessagesBanner(
            pinnedMessage: pin,
            pinnedMessageText: 'pinned content',
            onClose: () {},
          ),
        ),
      );
      expect(findSemanticsWithLabel('Close'), findsOneWidget);
    });

    testWidgets('BlockedChatBanner has the resolved label as semantics', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(BlockedChatBanner(onUnblock: () {})));
      // The banner's visible text + semantic label match (the visible
      // text is centered inside the InkWell; the wrapping Semantics
      // mirrors it so a screen reader reads the action once).
      expect(
        findSemanticsWithLabel(ChatUiLocalizations.en.blockedContactBannerText),
        findsOneWidget,
      );
    });
  });
}
