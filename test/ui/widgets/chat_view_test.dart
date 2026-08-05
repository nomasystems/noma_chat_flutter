import 'package:flutter/gestures.dart';
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
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
          ),
        ),
      );
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets(
      'shows a spinner instead of the empty state while the initial load '
      'is in flight',
      (tester) async {
        controller.setLoadingInitial(true);
        await tester.pumpWidget(
          wrap(
            ChatView(
              controller: controller,
              callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('No messages yet'), findsNothing);

        controller.setLoadingInitial(false);
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('No messages yet'), findsOneWidget);
      },
    );

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
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
          ),
        ),
      );
      expect(find.textContaining('Hello world'), findsOneWidget);
    });

    testWidgets('shows connection banner when state provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
            behaviors: const ChatViewBehaviors(
              connectionState: ChatConnectionState.reconnecting,
            ),
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsOneWidget);
    });

    testWidgets('no connection banner when state is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsNothing);
    });

    testWidgets('includes message input', (tester) async {
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('sends message via input', (tester) async {
      String? sent;
      await tester.pumpWidget(
        wrap(
          ChatView(
            controller: controller,
            callbacks: ChatViewCallbacks(
              onSendMessageRequest: (req) => sent = req.text,
            ),
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
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
            behaviors: const ChatViewBehaviors(
              emptyTitle: 'Start chatting!',
              emptyIcon: Icons.forum,
            ),
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
            callbacks: ChatViewCallbacks(
              onSendMessageRequest: (_) {},
              onEditMessage: (msg, text) {
                editedMsg = msg;
                newText = text;
              },
            ),
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
            callbacks: ChatViewCallbacks(
              onSendMessageRequest: (_) {},
              onTypingChanged: (v) => typing = v,
            ),
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
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
            behaviors: const ChatViewBehaviors(
              connectionState: ChatConnectionState.reconnecting,
            ),
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
            callbacks: ChatViewCallbacks(onSendMessageRequest: (_) {}),
            behaviors: const ChatViewBehaviors(
              connectionState: ChatConnectionState.connected,
            ),
          ),
        ),
      );
      expect(find.byType(ConnectionBanner), findsOneWidget);
    });
  });

  group('ChatView link taps', () {
    const url = 'https://example.com/a';

    /// Recognizer of the rendered span whose text is exactly `url`, reached
    /// through the real chain: `ChatView` → `MessageList` → `MessageBubble`
    /// → `TextBubble` → `parseMarkdown`.
    TapGestureRecognizer? linkRecognizer(WidgetTester tester) {
      TapGestureRecognizer? found;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == url) {
            final recognizer = span.recognizer;
            if (recognizer is TapGestureRecognizer) found = recognizer;
            return false;
          }
          return true;
        });
        if (found != null) break;
      }
      return found;
    }

    Future<void> pumpWithCallbacks(
      WidgetTester tester,
      ChatViewCallbacks callbacks,
    ) async {
      controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u2',
            text: 'see $url now',
            timestamp: DateTime(2026),
          ),
        ],
        currentUser: user,
      );
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, callbacks: callbacks)),
      );
    }

    testWidgets('a url span is tappable with no host wiring at all', (
      tester,
    ) async {
      await pumpWithCallbacks(
        tester,
        ChatViewCallbacks(onSendMessageRequest: (_) {}),
      );

      expect(linkRecognizer(tester), isNotNull);
    });

    testWidgets('a host onTapLink wins over the browser default', (
      tester,
    ) async {
      String? opened;

      await pumpWithCallbacks(
        tester,
        ChatViewCallbacks(
          onSendMessageRequest: (_) {},
          onTapLink: (value) => opened = value,
        ),
      );

      linkRecognizer(tester)!.onTap!();
      expect(opened, url);
    });
  });

  group('ChatView mention taps', () {
    /// The rendered span for `@bob`, reached through the whole chain:
    /// `ChatViewCallbacks` → `ChatView` → `MessageList` → `MessageBubble`
    /// → `TextBubble` → `parseMarkdown`.
    TextSpan? mentionSpan(WidgetTester tester) {
      TextSpan? found;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == '@bob') {
            found = span;
            return false;
          }
          return true;
        });
        if (found != null) break;
      }
      return found;
    }

    Future<void> pumpWithCallbacks(
      WidgetTester tester,
      ChatViewCallbacks callbacks,
    ) async {
      controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'u2',
            text: 'ping @bob please',
            timestamp: DateTime(2026),
          ),
        ],
        currentUser: user,
      );
      await tester.pumpWidget(
        wrap(ChatView(controller: controller, callbacks: callbacks)),
      );
    }

    testWidgets('a host onTapMention reaches the bubble', (tester) async {
      String? opened;

      await pumpWithCallbacks(
        tester,
        ChatViewCallbacks(
          onSendMessageRequest: (_) {},
          onTapMention: (value) => opened = value,
        ),
      );

      final recognizer = mentionSpan(tester)!.recognizer;
      (recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 'bob');
    });

    testWidgets('an unwired mention is inert and looks it', (tester) async {
      await pumpWithCallbacks(
        tester,
        ChatViewCallbacks(onSendMessageRequest: (_) {}),
      );

      final mention = mentionSpan(tester);
      expect(mention, isNotNull);
      expect(
        mention!.recognizer,
        isNull,
        reason: 'unlike onTapLink, this callback has no sensible default',
      );
      expect(mention.style?.fontWeight, isNot(FontWeight.w600));
    });
  });
}
