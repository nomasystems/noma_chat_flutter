import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  final parentMessage = ChatMessage(
    id: 'parent1',
    from: 'u2',
    timestamp: DateTime(2026, 1, 1),
    text: 'Parent message',
  );

  final reply1 = ChatMessage(
    id: 'reply1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 0, 1),
    text: 'First reply',
  );

  final reply2 = ChatMessage(
    id: 'reply2',
    from: 'u2',
    timestamp: DateTime(2026, 1, 1, 0, 2),
    text: 'Second reply',
  );

  group('ThreadView', () {
    testWidgets('renders parent message and replies', (tester) async {
      final controller = ChatController(
        initialMessages: [reply1, reply2],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.textContaining('Parent message'), findsOneWidget);
      expect(find.textContaining('First reply'), findsOneWidget);
      expect(find.textContaining('Second reply'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('shows thread header with title', (tester) async {
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.text('Thread'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('shows reply count in header', (tester) async {
      final controller = ChatController(
        initialMessages: [reply1, reply2],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            replies: [reply1, reply2],
            currentUserId: 'u1',
          ),
        ),
      );

      expect(find.text('2 replies'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('send reply triggers callback', (tester) async {
      String? sentText;
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            onSendReply: (text) {
              sentText = text;
              return true;
            },
            currentUserId: 'u1',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'My reply');
      await tester.pump();

      final sendButton = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.child is Container,
      );
      await tester.tap(sendButton.last);
      await tester.pump();

      expect(sentText, 'My reply');

      controller.dispose();
    });

    testWidgets('close button triggers onClose', (tester) async {
      var closed = false;
      final controller = ChatController(
        initialMessages: [],
        currentUser: currentUser,
      );

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            onClose: () => closed = true,
            currentUserId: 'u1',
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, true);

      controller.dispose();
    });
  });

  group('ThreadView inline taps', () {
    const url = 'https://example.com/a';

    /// The rendered span whose text is exactly [needle], reached through
    /// the real chain: `ThreadView` → `MessageBubble` → `TextBubble` →
    /// `parseMarkdown`. `null` also covers the bubble rendering through
    /// `SelectableText.rich`, which builds no [RichText] and dispatches no
    /// recognizer — the exact shape of the bug this group guards.
    TextSpan? spanFor(WidgetTester tester, String needle) {
      TextSpan? found;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == needle) {
            found = span;
            return false;
          }
          return true;
        });
        if (found != null) break;
      }
      return found;
    }

    ChatController replyController(String text) => ChatController(
      initialMessages: [
        ChatMessage(
          id: 'reply-link',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1, 0, 1),
          text: text,
        ),
      ],
      currentUser: currentUser,
    );

    testWidgets('a host onTapLink receives a tapped url in a reply', (
      tester,
    ) async {
      String? opened;
      final controller = replyController('see $url now');

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
            onTapLink: (value) => opened = value,
          ),
        ),
      );

      final recognizer = spanFor(tester, url)?.recognizer;
      expect(recognizer, isNotNull);
      (recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, url);

      controller.dispose();
    });

    testWidgets('a url in a reply is live with no host wiring at all', (
      tester,
    ) async {
      final controller = replyController('see $url now');

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(
        spanFor(tester, url)?.recognizer,
        isNotNull,
        reason:
            'threads default to the same system-browser handler as the '
            'timeline',
      );

      controller.dispose();
    });

    testWidgets('only the reply that needs a recognizer loses selection', (
      tester,
    ) async {
      final controller = replyController('see $url now');

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
          ),
        ),
      );

      expect(
        find.byType(SelectableText),
        findsOneWidget,
        reason: 'the plain parent stays selectable, the link reply does not',
      );

      controller.dispose();
    });

    testWidgets('a mention in a reply reaches the host handler', (
      tester,
    ) async {
      String? opened;
      final controller = replyController('ping @bob please');

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: parentMessage,
            controller: controller,
            currentUserId: 'u1',
            onTapMention: (value) => opened = value,
          ),
        ),
      );

      final recognizer = spanFor(tester, '@bob')?.recognizer;
      expect(recognizer, isNotNull);
      (recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 'bob');

      controller.dispose();
    });
  });
}
