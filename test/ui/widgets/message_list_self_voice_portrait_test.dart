import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The portrait inside one's own voice note.
///
/// It stays — WhatsApp paints the sender's picture inside the voice-note
/// bubble too, in a 1:1 and on one's own messages, so removing it would
/// have moved away from the baseline rather than towards it. What was
/// wrong is that it showed initials for an account that has a photo.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Chiara E2E');

  ChatMessage voiceNote() => ChatMessage(
    id: 'a1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 20, 30),
    messageType: MessageType.audio,
    attachmentUrl: 'https://cdn.example.com/note.m4a',
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  /// The portrait the audio bubble ended up painting, if any.
  UserAvatar? portrait(WidgetTester tester) {
    final avatars = tester.widgetList<UserAvatar>(find.byType(UserAvatar));
    return avatars.isEmpty ? null : avatars.first;
  }

  late ChatController controller;
  tearDown(() => controller.dispose());

  testWidgets('takes the photo the live resolver knows about', (tester) async {
    // The account has a picture, but it landed after the room was opened —
    // so the controller's snapshot of `currentUser` does not carry it and
    // never will. Only the resolver sees it.
    controller = ChatController(
      initialMessages: [voiceNote()],
      currentUser: me,
    );
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          avatarUrlResolver: (id) =>
              id == 'u1' ? 'https://cdn.example.com/me.png' : null,
        ),
      ),
    );

    expect(portrait(tester)?.imageUrl, 'https://cdn.example.com/me.png');
  });

  testWidgets('falls back to the controller copy when there is no resolver', (
    tester,
  ) async {
    controller = ChatController(
      initialMessages: [voiceNote()],
      currentUser: const ChatUser(
        id: 'u1',
        displayName: 'Chiara E2E',
        avatarUrl: 'https://cdn.example.com/snapshot.png',
      ),
    );
    await tester.pumpWidget(wrap(MessageList(controller: controller)));

    expect(portrait(tester)?.imageUrl, 'https://cdn.example.com/snapshot.png');
  });

  testWidgets('a resolver that knows nothing does not erase the copy', (
    tester,
  ) async {
    controller = ChatController(
      initialMessages: [voiceNote()],
      currentUser: const ChatUser(
        id: 'u1',
        displayName: 'Chiara E2E',
        avatarUrl: 'https://cdn.example.com/snapshot.png',
      ),
    );
    await tester.pumpWidget(
      wrap(
        MessageList(controller: controller, avatarUrlResolver: (_) => '   '),
      ),
    );

    expect(portrait(tester)?.imageUrl, 'https://cdn.example.com/snapshot.png');
  });

  testWidgets('with no picture anywhere it still shows the portrait slot', (
    tester,
  ) async {
    // The initials are the fallback, not the defect: the slot itself is
    // WhatsApp behaviour and must not disappear.
    controller = ChatController(
      initialMessages: [voiceNote()],
      currentUser: me,
    );
    await tester.pumpWidget(wrap(MessageList(controller: controller)));

    final avatar = portrait(tester);
    expect(avatar, isNotNull);
    expect(avatar!.imageUrl, isNull);
    expect(avatar.displayName, 'Chiara E2E');
  });
}
