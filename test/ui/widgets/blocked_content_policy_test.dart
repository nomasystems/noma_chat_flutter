import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Blocking someone used to be cosmetic inside a group: the name and the
/// avatar came off the bubble, but the text, the shared location and the
/// photo stayed exactly where they were, and nothing on screen said a
/// blocked person was in the room. These cover the pruning that replaced
/// that — group-only, the escape hatch for a host whose backend already
/// filters, and the 1:1 the pruning must keep its hands off.
///
/// Every surface the pruning reaches beyond this widget — the quote, the
/// reactions, the room notice, the room-list preview — is covered in
/// `blocked_content_surfaces_test.dart`, mounted over a real adapter.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const blocked = ChatUser(id: 'u-blocked', displayName: 'Blocked');
  const other = ChatUser(id: 'u2', displayName: 'Bob');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: [
        ChatMessage(
          id: 'm1',
          from: other.id,
          text: 'visible from bob',
          timestamp: DateTime(2026, 1, 1, 10),
        ),
        ChatMessage(
          id: 'm2',
          from: blocked.id,
          text: 'secret from the blocked one',
          timestamp: DateTime(2026, 1, 1, 10, 1),
        ),
        ChatMessage(
          id: 'm3',
          from: blocked.id,
          timestamp: DateTime(2026, 1, 1, 10, 2),
          messageType: MessageType.location,
          metadata: const {'lat': 40.4, 'lng': -3.7},
        ),
      ],
      currentUser: me,
      otherUsers: const [blocked, other],
    );
  });

  tearDown(() => controller.dispose());

  testWidgets('by default a blocked sender leaves a placeholder and no '
      'content at all', (tester) async {
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: true,
          blockedSenderIds: const {'u-blocked'},
        ),
      ),
    );

    expect(find.textContaining('secret from the blocked one'), findsNothing);
    expect(find.text('Message from a blocked user'), findsNWidgets(2));
    expect(find.textContaining('visible from bob'), findsOneWidget);
  });

  testWidgets('hide drops the rows entirely, placeholder and all', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: true,
          blockedSenderIds: const {'u-blocked'},
          blockedContentPolicy: BlockedContentPolicy.hide,
        ),
      ),
    );

    expect(find.textContaining('secret from the blocked one'), findsNothing);
    expect(find.text('Message from a blocked user'), findsNothing);
    expect(find.textContaining('visible from bob'), findsOneWidget);
  });

  testWidgets('show is the opt-out: nothing is pruned', (tester) async {
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: true,
          blockedSenderIds: const {'u-blocked'},
          blockedContentPolicy: BlockedContentPolicy.show,
        ),
      ),
    );

    expect(find.textContaining('secret from the blocked one'), findsOneWidget);
    expect(find.text('Message from a blocked user'), findsNothing);
  });

  testWidgets('a 1:1 is never pruned, whatever the policy says', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: false,
          blockedSenderIds: const {'u-blocked'},
        ),
      ),
    );

    expect(find.textContaining('secret from the blocked one'), findsOneWidget);
    expect(find.text('Message from a blocked user'), findsNothing);
  });

  testWidgets('an empty blocked set changes nothing', (tester) async {
    await tester.pumpWidget(
      wrap(MessageList(controller: controller, isGroup: true)),
    );

    expect(find.textContaining('secret from the blocked one'), findsOneWidget);
    expect(find.text('Message from a blocked user'), findsNothing);
  });

  testWidgets('the host can replace the placeholder', (tester) async {
    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: controller,
          isGroup: true,
          blockedSenderIds: const {'u-blocked'},
          blockedMessageBuilder: (context, message) => const Text('host pill'),
        ),
      ),
    );

    expect(find.text('host pill'), findsNWidgets(2));
    expect(find.text('Message from a blocked user'), findsNothing);
    expect(find.textContaining('secret from the blocked one'), findsNothing);
  });

  testWidgets('a system row is not the blocked person speaking, so it '
      'survives', (tester) async {
    final withSystem = ChatController(
      initialMessages: [
        ChatMessage(
          id: 's1',
          from: blocked.id,
          text: 'someone joined',
          timestamp: DateTime(2026, 1, 1, 10),
          messageType: MessageType.regular,
          isSystem: true,
        ),
      ],
      currentUser: me,
      otherUsers: const [blocked],
    );
    addTearDown(withSystem.dispose);

    await tester.pumpWidget(
      wrap(
        MessageList(
          controller: withSystem,
          isGroup: true,
          blockedSenderIds: const {'u-blocked'},
          blockedContentPolicy: BlockedContentPolicy.hide,
        ),
      ),
    );

    expect(find.text('Message from a blocked user'), findsNothing);
    expect(withSystem.messages.single.isSystem, isTrue);
  });
}
