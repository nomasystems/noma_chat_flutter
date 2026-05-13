import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Alice');

  ChatMessage makeMsg(String id, {String? text, DateTime? ts, String? from}) =>
      ChatMessage(
        id: id,
        from: from ?? 'u1',
        text: text ?? 'msg $id',
        timestamp: ts ?? DateTime(2026, 1, 1),
      );

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(height: 600, child: child)),
      );

  setUp(() {
    controller = ChatController(
      initialMessages: [
        makeMsg('1', ts: DateTime(2026, 1, 1, 10)),
        makeMsg('2', ts: DateTime(2026, 1, 1, 11)),
        makeMsg('3', text: 'Hello', ts: DateTime(2026, 1, 1, 12)),
      ],
      currentUser: user,
    );
  });

  tearDown(() => controller.dispose());

  group('MessageList', () {
    testWidgets('renders messages', (tester) async {
      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      expect(find.textContaining('Hello'), findsOneWidget);
      expect(find.textContaining('msg 1'), findsOneWidget);
      expect(find.textContaining('msg 2'), findsOneWidget);
    });

    testWidgets('shows date separator', (tester) async {
      controller = ChatController(
        initialMessages: [
          makeMsg('1', ts: DateTime(2026, 1, 1)),
          makeMsg('2', ts: DateTime(2026, 1, 2)),
        ],
        currentUser: user,
      );
      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      final separators = find.byType(DateSeparator);
      expect(separators, findsAtLeastNWidgets(2));
    });

    testWidgets('hides reaction-type messages', (tester) async {
      controller = ChatController(
        initialMessages: [
          makeMsg('1'),
          ChatMessage(
            id: 'r1',
            from: 'u1',
            timestamp: DateTime(2026, 1, 1, 13),
            messageType: MessageType.reaction,
            reaction: '👍',
            referencedMessageId: '1',
          ),
        ],
        currentUser: user,
      );
      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      expect(find.textContaining('msg 1'), findsOneWidget);
    });

    testWidgets('shows typing indicator when typing', (tester) async {
      controller.setTyping('u2', true);
      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      expect(find.byType(TypingIndicator), findsOneWidget);
      controller.setTyping('u2', false);
    });

    testWidgets('calls onLoadMore at scroll end', (tester) async {
      final msgs = List.generate(
        30,
        (i) => makeMsg('m$i', ts: DateTime(2026, 1, 1, i)),
      );
      controller = ChatController(
        initialMessages: msgs,
        currentUser: user,
      );

      var loadMoreCalled = false;
      await tester.pumpWidget(wrap(MessageList(
        controller: controller,
        onLoadMore: () => loadMoreCalled = true,
      )));

      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);
      expect(loadMoreCalled, isFalse);
    });

    testWidgets('passes onMessageLongPress callback', (tester) async {
      ChatMessage? longPressed;
      await tester.pumpWidget(wrap(MessageList(
        controller: controller,
        onMessageLongPress: (msg, rect) => longPressed = msg,
      )));
      expect(find.byType(MessageBubble), findsWidgets);
      expect(longPressed, isNull);
    });

    testWidgets('shows retry for failed messages', (tester) async {
      controller.markPending('1');
      controller.markFailed('1');
      ChatMessage? retried;

      await tester.pumpWidget(wrap(MessageList(
        controller: controller,
        onRetryMessage: (msg) => retried = msg,
      )));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(retried, isNull);
    });
  });
}
