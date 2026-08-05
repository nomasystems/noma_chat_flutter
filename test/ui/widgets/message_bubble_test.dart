import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage makeMessage({
    String text = 'Hello',
    Map<String, dynamic>? metadata,
    bool isSystem = false,
    bool isEdited = false,
    bool isForwarded = false,
  }) {
    return ChatMessage(
      id: 'msg1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: text,
      metadata: metadata,
      isSystem: isSystem,
      isEdited: isEdited,
      isForwarded: isForwarded,
    );
  }

  group('MessageBubble', () {
    testWidgets('renders text bubble for regular message', (tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: makeMessage(), isOutgoing: false)),
      );

      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('renders system message as centered text', (tester) async {
      final msg = makeMessage(
        text: 'u1 joined',
        isSystem: true,
        metadata: {'event': 'user_joined', 'userId': 'u1'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.text('u1 joined'), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('shows sender name when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            senderName: 'Alice',
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows pending icon when isPending=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isPending: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows error icon when isFailed=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isFailed: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('reduced top padding when isFirstInGroup=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: true,
              ),
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: false,
              ),
            ],
          ),
        ),
      );

      final paddings = tester
          .widgetList<Padding>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding is EdgeInsets &&
                  (widget.padding as EdgeInsets).left == 8 &&
                  (widget.padding as EdgeInsets).right == 8,
            ),
          )
          .toList();

      expect(paddings.length, 2);
      final firstTop = (paddings[0].padding as EdgeInsets).top;
      final secondTop = (paddings[1].padding as EdgeInsets).top;

      expect(firstTop, 8.0);
      expect(secondTop, 4.0);
    });

    testWidgets('renders LocationBubble for MessageType.location', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
        metadata: const {'lat': '40.4168', 'lng': '-3.7038'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsOneWidget);
    });

    testWidgets('falls back when location metadata is missing', (tester) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsNothing);
    });
  });

  group('Read receipt avatars', () {
    testWidgets(
      'renders ReadReceiptAvatars when readReceiptUsers is non-empty',
      (tester) async {
        final msg = makeMessage();
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg,
              isOutgoing: true,
              status: ReceiptStatus.read,
              readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
              readReceipts: [
                ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
              ],
            ),
          ),
        );

        expect(find.byType(ReadReceiptAvatars), findsOneWidget);
      },
    );

    testWidgets('does not render avatars when readReceiptUsers is empty', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            status: ReceiptStatus.read,
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });

    testWidgets('does not render avatars while the message is pending', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            isPending: true,
            readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
            readReceipts: [
              ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
            ],
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });
  });

  group('MessageBubble link taps', () {
    const url = 'https://example.com/a';

    /// Finds the recognizer attached to the rendered span whose text is
    /// exactly `url`. `null` means the span was painted as a link but left
    /// unclickable — the shape of the bug this group guards.
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

    testWidgets('forwards onTapLink to the text bubble it builds', (
      tester,
    ) async {
      String? opened;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'see $url now'),
            isOutgoing: false,
            onSwipeToReply: () {},
            onTapLink: (value) => opened = value,
          ),
        ),
      );

      final recognizer = linkRecognizer(tester);
      expect(recognizer, isNotNull);

      recognizer!.onTap!();
      expect(opened, url);
    });

    testWidgets('leaves the url span without a recognizer when unwired', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'see $url now'),
            isOutgoing: false,
            onSwipeToReply: () {},
          ),
        ),
      );

      expect(linkRecognizer(tester), isNull);
    });
  });

  group('MessageBubble mention taps', () {
    /// The rendered span for a given piece of the message text, reached
    /// through the real chain: `MessageBubble` → `TextBubble` →
    /// `parseMarkdown`.
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

    testWidgets('forwards onTapMention to the text bubble it builds', (
      tester,
    ) async {
      String? opened;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'hi @alice!'),
            isOutgoing: false,
            onSwipeToReply: () {},
            onTapMention: (value) => opened = value,
          ),
        ),
      );

      final mention = spanFor(tester, '@alice');
      expect(mention, isNotNull);
      expect(mention!.style?.fontWeight, FontWeight.w600);

      (mention.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 'alice');
    });

    testWidgets('paints no tappable affordance when unwired', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'hi @alice!'),
            isOutgoing: false,
            onSwipeToReply: () {},
          ),
        ),
      );

      final mention = spanFor(tester, '@alice');
      expect(mention, isNotNull);
      expect(mention!.recognizer, isNull);
      expect(
        mention.style,
        spanFor(tester, 'hi ')?.style,
        reason: 'an unhandled mention reads exactly like the words around it',
      );
    });
  });
}
