import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('MessageBubble a11y', () {
    testWidgets('outgoing read message exposes "You: hola, Read" label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'hola',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.read);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(findSemanticsWithLabel('You: hola, Read'), findsOneWidget);
    });

    testWidgets(
      'outgoing delivered message includes Delivered status in label',
      (tester) async {
        final message = fixtureMessage(
          text: 'hello',
          from: fixtureUserMe.id,
        ).copyWith(receipt: ReceiptStatus.delivered);

        await tester.pumpWidget(
          wrap(MessageBubble(message: message, isOutgoing: true)),
        );

        expect(findSemanticsWithLabel('You: hello, Delivered'), findsOneWidget);
      },
    );

    testWidgets('outgoing sent message includes Sent status in label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'ping',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(findSemanticsWithLabel('You: ping, Sent'), findsOneWidget);
    });

    testWidgets('incoming message uses sender name as prefix without status', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'qué tal',
        from: fixtureUserOther.id,
      );

      await tester.pumpWidget(
        wrap(
          MessageBubble(message: message, isOutgoing: false, senderName: 'Bob'),
        ),
      );

      expect(findSemanticsWithLabel('Bob: qué tal'), findsOneWidget);
    });

    testWidgets('deleted outgoing message omits status from semantic label', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'oops',
        from: fixtureUserMe.id,
      ).copyWith(isDeleted: true, receipt: ReceiptStatus.read);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(
        findSemanticsWithLabel('You: This message was deleted'),
        findsOneWidget,
      );
    });
  });

  // Regression coverage for the "everything is trapped behind
  // `excludeSemantics: true`" bug: the long-press menu, the retry icon, an
  // attachment's open action and reactions were all unreachable with a
  // screen reader because they lived inside the bubble's excluded
  // subtree with no equivalent action re-declared on the outer node.
  // These tests drive the real semantics tree (`tester.semantics`), not
  // just the widget tree, and fail if that wiring regresses.
  group('MessageBubble a11y — reachable actions', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('long-press context menu is reachable as a semantics action', (
      tester,
    ) async {
      var longPressed = false;
      final message = fixtureMessage(text: 'hola', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            onLongPress: () => longPressed = true,
          ),
        ),
      );

      tester.semantics.performAction(
        find.semantics.byLabel('Bob: hola'),
        SemanticsAction.longPress,
      );

      expect(longPressed, isTrue);
    });

    testWidgets('failed outgoing message exposes a Retry custom action', (
      tester,
    ) async {
      var retried = false;
      final message = fixtureMessage(text: 'oops', from: fixtureUserMe.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: true,
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      const retryAction = CustomSemanticsAction(label: 'Retry');
      tester.semantics.performAction(
        find.semantics.byLabel('You: oops, Failed'),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(retryAction),
      );

      expect(retried, isTrue);
    });

    testWidgets(
      'image message exposes opening the attachment as its tap action',
      (tester) async {
        var opened = false;
        final message = fixtureMessage(
          text: null,
          from: fixtureUserOther.id,
          messageType: MessageType.attachment,
          mimeType: 'image/jpeg',
          attachmentUrl: 'https://example.com/a.jpg',
        );

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message,
              isOutgoing: false,
              senderName: 'Bob',
              onTapImage: () => opened = true,
            ),
          ),
        );

        tester.semantics.performAction(
          find.semantics.byLabel('Bob: Photo'),
          SemanticsAction.tap,
        );

        expect(opened, isTrue);
      },
    );

    testWidgets('a reaction pill keeps its own reachable semantics node', (
      tester,
    ) async {
      var tappedEmoji = '';
      final message = fixtureMessage(text: 'hi', from: fixtureUserOther.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: false,
            senderName: 'Bob',
            reactions: const {'👍': 1},
            onReactionTap: (emoji) => tappedEmoji = emoji,
          ),
        ),
      );

      tester.semantics.performAction(
        find.semantics.byLabel('👍 1'),
        SemanticsAction.tap,
      );

      expect(tappedEmoji, '👍');
    });

    testWidgets(
      'the thread reply-count row keeps its own reachable semantics node',
      (tester) async {
        var tappedThread = false;
        final message = fixtureMessage(text: 'root', from: fixtureUserOther.id);

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message,
              isOutgoing: false,
              senderName: 'Bob',
              replyCount: 3,
              onTapThread: () => tappedThread = true,
            ),
          ),
        );

        tester.semantics.performAction(
          find.semantics.byLabel('3 replies'),
          SemanticsAction.tap,
        );

        expect(tappedThread, isTrue);
      },
    );
  });
}
