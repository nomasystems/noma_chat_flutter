import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// D1 — swiping/selecting reply (or long-pressing edit) puts the caret
/// straight in the composer, matching every other chat app. Before this
/// fix `MessageInput` had no `FocusNode` at all, so `setReplyTo`/
/// `setEditingMessage` never pulled up the keyboard.
void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Alice');
  final otherMessage = ChatMessage(
    id: 'm1',
    from: 'u2',
    timestamp: DateTime(2026, 1, 1),
    text: 'Hi there',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(
      initialMessages: [otherMessage],
      currentUser: user,
    );
  });

  tearDown(() => controller.dispose());

  testWidgets('requests focus when replyingTo transitions null -> non-null', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, false);

    controller.setReplyTo(otherMessage);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      true,
    );
  });

  testWidgets('requests focus when editingMessage transitions null -> '
      'non-null', (tester) async {
    final myMessage = ChatMessage(
      id: 'm2',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: 'Mine',
    );
    controller.addMessage(myMessage);
    await tester.pumpWidget(
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
    );

    controller.setEditingMessage(myMessage);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      true,
    );
  });

  testWidgets('does not steal focus when neither reply nor edit is active '
      '(no behaviour change)', (tester) async {
    await tester.pumpWidget(
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      false,
    );
  });

  testWidgets('clearing the reply does not leave focus stuck requesting '
      'again on unrelated rebuilds', (tester) async {
    await tester.pumpWidget(
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
    );
    controller.setReplyTo(otherMessage);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      true,
    );

    // Explicitly drop focus, then trigger an unrelated notifyListeners
    // (clearing reply) — must not re-request focus since replyingTo did
    // not go null -> non-null again.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    controller.setReplyTo(null);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      false,
    );
  });
}
