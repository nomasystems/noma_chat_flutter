import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// default group avatars in `MessageList`.
///
/// When the consumer doesn't provide an `avatarBuilder` AND the room
/// is a group AND the bubble is incoming AND it's the last in a
/// burst, `MessageList` renders a [UserAvatar] showing the sender's
/// initials.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');
  const bob = ChatUser(id: 'u2', displayName: 'Bob');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  ChatMessage incoming(
    String id,
    String from, {
    Duration offset = Duration.zero,
  }) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1).add(offset),
    text: 'msg $id',
  );

  testWidgets(
    'Group + incoming + last in burst → default UserAvatar rendered',
    (tester) async {
      final controller = ChatController(
        initialMessages: [incoming('m1', 'u1')],
        currentUser: me,
        otherUsers: const [alice, bob],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));

      // At least one UserAvatar from MessageList default fallback.
      expect(find.byType(UserAvatar), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('DM (otherUsers.length == 1) → no avatar in bubble row', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: [incoming('m1', 'u1')],
      currentUser: me,
      otherUsers: const [alice], // 1:1 — not a group.
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(MessageList(controller: controller)));

    // The bubble itself never renders an avatar in DMs (the default
    // fallback is gated by `isGroup`).
    expect(find.byType(UserAvatar), findsNothing);
  });

  testWidgets('Custom avatarBuilder takes precedence over the default', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: [incoming('m1', 'u1')],
      currentUser: me,
      otherUsers: const [alice, bob],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          avatarBuilder: (context, userId) => Container(
            key: ValueKey('custom-$userId'),
            width: 24,
            height: 24,
            color: Colors.pink,
          ),
        ),
      ),
    );

    // The pink container appears for the incoming sender.
    expect(find.byKey(const ValueKey('custom-u1')), findsOneWidget);
  });
}
