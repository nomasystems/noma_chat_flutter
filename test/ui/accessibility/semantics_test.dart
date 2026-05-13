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
      final room = RoomListItem(id: 'r1', name: 'Team Chat');

      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(findSemanticsWithLabel('Team Chat'), findsOneWidget);
    });

    testWidgets('RoomTile uses id as semantic label when name is null', (
      tester,
    ) async {
      final room = RoomListItem(id: 'room-xyz');

      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(findSemanticsWithLabel('room-xyz'), findsOneWidget);
    });

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
        MaterialApp(home: Scaffold(body: const VoiceRecorderButton())),
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
            body: MessageInput(controller: controller, onSendMessage: (_) {}),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      expect(findSemanticsWithLabel('Send'), findsOneWidget);

      controller.dispose();
    });
  });
}
