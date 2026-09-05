import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// [ChatView]'s composer-vs-notice swap for an `owner_only` room: the
/// same read-only band [ChatViewBehaviors.readOnly] already drove for an
/// announcement channel or a moderation mute, now also driven by
/// [RoomWritePolicy]. Carries the `chat_read_only_notice` semantics
/// identifier so a host — or an accessibility audit — can find it
/// regardless of which of the three reasons produced it, and a
/// [ChatViewBuilders.readOnlyNoticeBuilder] can replace it per reason.
void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Me');

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(initialMessages: const [], currentUser: user);
  });

  tearDown(() => controller.dispose());

  Widget viewFor(
    RoomListItem room, {
    ReadOnlyNoticeBuilder? readOnlyNoticeBuilder,
  }) => ChatView(
    controller: controller,
    callbacks: ChatViewCallbacks(onSendMessageRequest: (_) => true),
    builders: ChatViewBuilders(readOnlyNoticeBuilder: readOnlyNoticeBuilder),
    behaviors: const ChatViewBehaviors().withRoomState(
      initialMessageId: null,
      unreadBoundaryMessageId: null,
      unreadCount: 0,
      isBlocked: false,
      isParticipating: true,
      readOnly: room.isReadOnly,
      readOnlyLabel: null,
      readOnlyReason: room.writePolicy == RoomWritePolicy.ownerOnly
          ? ReadOnlyReason.ownerOnly
          : null,
      isGroup: room.isGroup,
    ),
  );

  group('owner_only room, viewer is a plain member', () {
    const room = RoomListItem(
      id: 'room1',
      writePolicy: RoomWritePolicy.ownerOnly,
      userRole: RoomRole.member,
    );

    testWidgets('hides the composer', (tester) async {
      await tester.pumpWidget(wrap(viewFor(room)));
      expect(find.byType(MessageInput), findsNothing);
    });

    testWidgets(
      'paints the default notice, exposed under chat_read_only_notice and '
      'localized through ChatUiLocalizations',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(wrap(viewFor(room)));

        final node = tester.getSemantics(
          find.bySemanticsIdentifier('chat_read_only_notice'),
        );
        expect(node.label, ChatUiLocalizations.en.readOnlyChannel);
        expect(
          find.text(ChatUiLocalizations.en.readOnlyChannel),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('a host readOnlyNoticeBuilder replaces the default notice', (
      tester,
    ) async {
      ReadOnlyReason? seenReason;
      await tester.pumpWidget(
        wrap(
          viewFor(
            room,
            readOnlyNoticeBuilder: (context, reason) {
              seenReason = reason;
              return const Text('Custom closed-room notice');
            },
          ),
        ),
      );

      expect(seenReason, ReadOnlyReason.ownerOnly);
      expect(find.text('Custom closed-room notice'), findsOneWidget);
      expect(find.text(ChatUiLocalizations.en.readOnlyChannel), findsNothing);
    });

    testWidgets(
      'a readOnlyNoticeBuilder returning null falls back to the default',
      (tester) async {
        await tester.pumpWidget(
          wrap(viewFor(room, readOnlyNoticeBuilder: (context, reason) => null)),
        );
        expect(
          find.text(ChatUiLocalizations.en.readOnlyChannel),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('owner_only room is writable for its owner: composer stays', (
    tester,
  ) async {
    const room = RoomListItem(
      id: 'room1',
      writePolicy: RoomWritePolicy.ownerOnly,
      userRole: RoomRole.owner,
    );
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(viewFor(room)));
    expect(find.byType(MessageInput), findsOneWidget);
    expect(find.bySemanticsIdentifier('chat_read_only_notice'), findsNothing);
    handle.dispose();
  });
}
