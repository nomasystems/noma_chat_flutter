import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Regression coverage for the missing live-region announcement: a chat
/// left open with TalkBack/VoiceOver never announced newly-arrived
/// incoming messages, unlike `TypingIndicator`/`ConnectionBanner` which
/// already used `Semantics(liveRegion: true)` for their own state changes.
void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Alice');
  const otherUser = ChatUser(id: 'u2', displayName: 'Bob');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  List<String?> liveRegionLabels(WidgetTester tester) => tester
      .widgetList<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      )
      .map((w) => w.properties.label)
      .toList();

  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: [
        ChatMessage(
          id: '1',
          from: otherUser.id,
          text: 'hi there',
          timestamp: DateTime(2026, 1, 1, 10),
        ),
      ],
      currentUser: currentUser,
      otherUsers: const [otherUser],
    );
  });

  tearDown(() => controller.dispose());

  group('MessageList a11y — new message announcements', () {
    testWidgets(
      'opening a chat with existing history does not announce anything',
      (tester) async {
        await tester.pumpWidget(wrap(MessageList(controller: controller)));

        expect(liveRegionLabels(tester), everyElement(isEmpty));
      },
    );

    testWidgets(
      'a newly-arrived incoming message updates the live region label',
      (tester) async {
        await tester.pumpWidget(wrap(MessageList(controller: controller)));
        expect(liveRegionLabels(tester), everyElement(isEmpty));

        controller.addMessage(
          ChatMessage(
            id: '2',
            from: otherUser.id,
            text: 'surprise!',
            timestamp: DateTime(2026, 1, 1, 11),
          ),
        );
        await tester.pumpWidget(wrap(MessageList(controller: controller)));
        await tester.pump();

        expect(liveRegionLabels(tester), contains('Bob: surprise!'));
      },
    );

    testWidgets('sending your own outgoing message does not self-announce', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(MessageList(controller: controller)));

      controller.addMessage(
        ChatMessage(
          id: '3',
          from: currentUser.id,
          text: 'my own reply',
          timestamp: DateTime(2026, 1, 1, 12),
        ),
      );
      await tester.pumpWidget(wrap(MessageList(controller: controller)));
      await tester.pump();

      expect(liveRegionLabels(tester), everyElement(isEmpty));
    });
  });
}
