import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// `MentionOverlay` wired into `MessageInput`.
///
/// Validates the composer's `@`-token detector and the insertion path
/// the overlay drives.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');
  const bob = ChatUser(id: 'u2', displayName: 'Bob');

  ChatController makeController() => ChatController(
    initialMessages: const [],
    currentUser: me,
    otherUsers: const [alice, bob],
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SafeArea(child: child)),
  );

  testWidgets('enableMentions=false: typing @ never shows the overlay', (
    tester,
  ) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
          // Mentions disabled (default).
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '@a');
    await tester.pump();

    expect(find.byType(MentionOverlay), findsNothing);
  });

  testWidgets('enableMentions=true + matching query renders MentionOverlay', (
    tester,
  ) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
          enableMentions: true,
          mentionUsers: const [alice, bob],
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '@a');
    await tester.pump();

    expect(find.byType(MentionOverlay), findsOneWidget);
    // Filter case-insensitive: 'a' matches 'Alice', not 'Bob'.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('tap on a mention candidate inserts "@Name " and dismisses '
      'the overlay', (tester) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
          enableMentions: true,
          mentionUsers: const [alice, bob],
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '@a');
    await tester.pump();
    expect(find.byType(MentionOverlay), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pump();

    // The composer rewrote "@a" → "@Alice " in the field.
    final widget = tester.widget<TextField>(field);
    expect(widget.controller!.text, '@Alice ');
    // Overlay collapsed after the selection.
    expect(find.byType(MentionOverlay), findsNothing);
  });

  testWidgets('@ preceded by a non-whitespace character does not activate '
      'the overlay (mid-word @ is not a mention)', (tester) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
          enableMentions: true,
          mentionUsers: const [alice, bob],
        ),
      ),
    );

    final field = find.byType(TextField);
    // 'hi@a' — the @ is glued to 'i', so it shouldn't open a mention.
    await tester.enterText(field, 'hi@a');
    await tester.pump();

    expect(find.byType(MentionOverlay), findsNothing);
  });

  testWidgets('finishing the mention with a space closes the overlay', (
    tester,
  ) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
          enableMentions: true,
          mentionUsers: const [alice, bob],
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '@a');
    await tester.pump();
    expect(find.byType(MentionOverlay), findsOneWidget);

    // User decides to abandon the mention and writes a space.
    await tester.enterText(field, '@a ');
    await tester.pump();
    expect(find.byType(MentionOverlay), findsNothing);
  });
}
