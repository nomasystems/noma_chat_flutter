import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// D91 — the quote a reply carries said nothing about WHO it quotes, tapping
/// it did nothing when the target was off screen or already visible, and the
/// bubble's accessibility label omitted the quote entirely.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const bob = ChatUser(id: 'u2', displayName: 'Bob');

  ChatMessage msg(
    String id, {
    String from = 'u2',
    String text = 'msg',
    DateTime? ts,
    MessageType type = MessageType.regular,
    String? referencedMessageId,
  }) => ChatMessage(
    id: id,
    from: from,
    text: text,
    timestamp: ts ?? DateTime(2026, 1, 1, 12),
    messageType: type,
    referencedMessageId: referencedMessageId,
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, width: 400, child: child)),
  );

  group('who the quote belongs to', () {
    testWidgets('a reply to MY OWN message names me on the strip', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: [
          msg('a', from: 'u1', text: 'mine', ts: DateTime(2026, 1, 1, 10)),
          msg(
            'b',
            text: 'answering you',
            ts: DateTime(2026, 1, 1, 11),
            type: MessageType.reply,
            referencedMessageId: 'a',
          ),
        ],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      await tester.pump();

      expect(find.byType(ReplyPreview), findsOneWidget);
      expect(
        tester.widget<ReplyPreview>(find.byType(ReplyPreview)).senderName,
        'You',
      );
      controller.dispose();
    });

    testWidgets('a reply to somebody else still names them', (tester) async {
      final controller = ChatController(
        initialMessages: [
          msg('a', text: 'theirs', ts: DateTime(2026, 1, 1, 10)),
          msg(
            'b',
            from: 'u1',
            text: 'answering Bob',
            ts: DateTime(2026, 1, 1, 11),
            type: MessageType.reply,
            referencedMessageId: 'a',
          ),
        ],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      await tester.pump();

      expect(
        tester.widget<ReplyPreview>(find.byType(ReplyPreview)).senderName,
        'Bob',
      );
      controller.dispose();
    });

    testWidgets('a blocked quoted sender stays unnamed', (tester) async {
      final controller = ChatController(
        initialMessages: [
          msg('a', text: 'theirs', ts: DateTime(2026, 1, 1, 10)),
          msg(
            'b',
            from: 'u1',
            text: 'answering',
            ts: DateTime(2026, 1, 1, 11),
            type: MessageType.reply,
            referencedMessageId: 'a',
          ),
        ],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);
      controller.setIsGroup(true);

      await tester.pumpWidget(
        wrap(
          MessageList(
            controller: controller,
            isGroup: true,
            blockedSenderIds: const {'u2'},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<ReplyPreview>(find.byType(ReplyPreview)).senderName,
        isNull,
      );
      controller.dispose();
    });

    testWidgets('the COMPOSER strip names who you are answering too', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: [msg('a', text: 'theirs')],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);
      controller.setReplyTo(msg('a', text: 'theirs'));

      await tester.pumpWidget(wrap(MessageInput(controller: controller)));
      await tester.pump();

      expect(
        tester.widget<ReplyPreview>(find.byType(ReplyPreview)).senderName,
        'Bob',
      );
      controller.dispose();
    });

    testWidgets('the composer names YOU when you answer yourself', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: [msg('a', from: 'u1', text: 'mine')],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);
      controller.setReplyTo(msg('a', from: 'u1', text: 'mine'));

      await tester.pumpWidget(wrap(MessageInput(controller: controller)));
      await tester.pump();

      expect(
        tester.widget<ReplyPreview>(find.byType(ReplyPreview)).senderName,
        'You',
      );
      controller.dispose();
    });
  });

  group('tapping the quote', () {
    testWidgets('highlights the target even when it is already on screen', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: [
          msg('a', text: 'the original', ts: DateTime(2026, 1, 1, 10)),
          msg(
            'b',
            from: 'u1',
            text: 'the answer',
            ts: DateTime(2026, 1, 1, 11),
            type: MessageType.reply,
            referencedMessageId: 'a',
          ),
        ],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      await tester.pump();

      expect(controller.highlightedMessageId, isNull);

      await tester.tap(find.byType(ReplyPreview));
      await tester.pump();

      expect(controller.highlightedMessageId, 'a');
      controller.dispose();
    });

    testWidgets('a target that is loaded but not built still gets a signal', (
      tester,
    ) async {
      final history = <ChatMessage>[
        msg('a', text: 'the original', ts: DateTime(2026, 1, 1, 0)),
        for (var i = 1; i < 60; i++)
          msg('m$i', text: 'filler $i', ts: DateTime(2026, 1, 1, 0, i)),
      ];
      final controller = ChatController(
        initialMessages: [
          ...history,
          msg(
            'reply',
            from: 'u1',
            text: 'the answer',
            ts: DateTime(2026, 1, 2),
            type: MessageType.reply,
            referencedMessageId: 'a',
          ),
        ],
        currentUser: me,
      );
      controller.setOtherUsers([bob]);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      await tester.pump();

      // The quoted row sits ~60 messages up: outside the viewport and
      // outside the default cache, so its GlobalKey has no context.
      await tester.tap(find.byType(ReplyPreview));
      await tester.pump();

      expect(controller.highlightedMessageId, 'a');
      controller.dispose();
    });
  });

  group('what a screen reader hears', () {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    testWidgets('the reply bubble announces the quote before its own body', (
      tester,
    ) async {
      final quoted = msg('a', text: 'where shall we meet?');
      final reply = msg(
        'b',
        from: 'u1',
        text: 'at the square',
        type: MessageType.reply,
        referencedMessageId: 'a',
      );

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: reply,
            isOutgoing: true,
            referencedMessage: quoted,
            referencedSenderName: 'Bob',
          ),
        ),
      );

      expect(
        semanticsWithLabel(
          'You: Replying to Bob: where shall we meet?. at the square',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unnamed quoted author drops the name, not the quote', (
      tester,
    ) async {
      final quoted = msg('a', text: 'where shall we meet?');
      final reply = msg(
        'b',
        from: 'u1',
        text: 'at the square',
        type: MessageType.reply,
        referencedMessageId: 'a',
      );

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: reply,
            isOutgoing: true,
            referencedMessage: quoted,
          ),
        ),
      );

      expect(
        semanticsWithLabel(
          'You: Replying to: where shall we meet?. at the square',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a plain message is read exactly as it always was', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg('a', from: 'u1', text: 'hola'),
            isOutgoing: true,
          ),
        ),
      );

      expect(semanticsWithLabel('You: hola'), findsOneWidget);
    });
  });
}
