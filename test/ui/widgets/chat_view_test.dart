import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Alice');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  setUp(() {
    controller = ChatController(initialMessages: [], currentUser: user);
  });

  tearDown(() => controller.dispose());

  group('ChatView', () {
    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('shows messages when present', (tester) async {
      controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u1',
            text: 'Hello world',
            timestamp: DateTime(2026),
          ),
        ],
        currentUser: user,
      );
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );
      expect(find.textContaining('Hello world'), findsOneWidget);
    });

    testWidgets('shows connection banner when state provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            connectionState: ChatConnectionState.reconnecting,
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsOneWidget);
    });

    testWidgets('no connection banner when state is null', (tester) async {
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );
      expect(find.byType(ConnectionBanner), findsNothing);
    });

    testWidgets('includes message input', (tester) async {
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('sends message via input', (tester) async {
      String? sent;
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (text) => sent = text,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(sent, 'Test message');
    });

    testWidgets('uses custom empty state', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            emptyTitle: 'Start chatting!',
            emptyIcon: Icons.forum,
          ),
        ),
      );
      expect(find.text('Start chatting!'), findsOneWidget);
      expect(find.byIcon(Icons.forum), findsOneWidget);
    });

    testWidgets('passes onEditMessage through to input', (tester) async {
      ChatMessage? editedMsg;
      String? newText;

      controller = ChatController(initialMessages: [], currentUser: user);

      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            onEditMessage: (msg, text) {
              editedMsg = msg;
              newText = text;
            },
          ),
        ),
      );

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Old text',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'New text');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(editedMsg?.id, 'm1');
      expect(newText, 'New text');
    });

    testWidgets('passes onTypingChanged through', (tester) async {
      bool? typing;
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            onTypingChanged: (v) => typing = v,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump();
      expect(typing, true);
    });

    testWidgets('shows reconnecting banner', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            connectionState: ChatConnectionState.reconnecting,
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsOneWidget);
    });

    testWidgets('does not show connection banner when connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            onSendMessage: (_) {},
            connectionState: ChatConnectionState.connected,
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsOneWidget);
    });
  });
}
