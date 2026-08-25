import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A room with nothing in it used to be a dead end: an icon, a line of text
/// and no way forward. It is now a starting card the host can fill in
/// through `ChatViewBuilders.emptyRoomBuilder`, with an SDK default that
/// offers the first message itself.
void main() {
  late ChatController controller;
  final sent = <String>[];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    sent.clear();
    controller = ChatController(
      initialMessages: const [],
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Alice')],
    );
  });

  tearDown(() => controller.dispose());

  Widget viewWith({
    EmptyRoomBuilder? emptyRoomBuilder,
    bool readOnly = false,
    bool? isGroup,
    String? emptyTitle,
    String? emptySubtitle,
    bool canSend = true,
  }) => ChatView(
    controller: controller,
    builders: ChatViewBuilders(emptyRoomBuilder: emptyRoomBuilder),
    callbacks: ChatViewCallbacks(
      onSendMessageRequest: canSend
          ? (req) {
              sent.add(req.text);
              return true;
            }
          : null,
    ),
    behaviors: ChatViewBehaviors(
      readOnly: readOnly,
      isGroup: isGroup,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      enableLinkPreview: false,
    ),
  );

  group('empty room card', () {
    testWidgets('a 1:1 with no messages offers the first message', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(viewWith()));

      final chip = find.byKey(const Key('chat_empty_room_suggestion_0'));
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pump();

      expect(sent, ['👋']);
    });

    testWidgets('a room that already has messages shows the list instead', (
      tester,
    ) async {
      var builderCalls = 0;
      controller.addMessage(
        ChatMessage(
          id: 'm1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'hi',
        ),
      );

      await tester.pumpWidget(
        wrap(
          viewWith(
            emptyRoomBuilder: (context, room) {
              builderCalls++;
              return const Text('host card');
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MessageList), findsOneWidget);
      expect(find.byKey(EmptyRoomState.rootKey), findsNothing);
      expect(builderCalls, 0);
      expect(find.text('host card'), findsNothing);
    });

    testWidgets('emptyRoomBuilder replaces the SDK card', (tester) async {
      late EmptyRoomInfo seen;
      await tester.pumpWidget(
        wrap(
          viewWith(
            emptyRoomBuilder: (context, room) {
              seen = room;
              return EmptyRoomState(
                title: 'Padel on Friday',
                header: const Text('Organised by Alice'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Share plan')),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('Padel on Friday'), findsOneWidget);
      expect(find.text('Organised by Alice'), findsOneWidget);
      expect(find.text('Share plan'), findsOneWidget);
      expect(
        find.byKey(const Key('chat_empty_room_suggestion_0')),
        findsNothing,
      );
      expect(seen.isGroup, isFalse);
      expect(seen.otherUser?.displayName, 'Alice');
      expect(seen.onSendFirstMessage, isNotNull);

      seen.onSendFirstMessage!('Are you in?');
      expect(sent, ['Are you in?']);
    });

    testWidgets('a builder that returns null falls back to the SDK card', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(viewWith(emptyRoomBuilder: (context, room) => null)),
      );

      expect(find.byType(DefaultEmptyRoomState), findsOneWidget);
      expect(
        find.byKey(const Key('chat_empty_room_suggestion_0')),
        findsOneWidget,
      );
    });

    testWidgets('host empty labels still win over the SDK ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(viewWith(emptyTitle: 'Nothing here', emptySubtitle: 'Yet')),
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Yet'), findsOneWidget);
    });

    testWidgets('a room that cannot be written to offers nothing to send', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(viewWith(readOnly: true)));

      expect(find.byKey(EmptyRoomState.rootKey), findsOneWidget);
      expect(
        find.byKey(const Key('chat_empty_room_suggestion_0')),
        findsNothing,
      );
    });

    testWidgets('a group gets the card without the 1:1 greeting', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(viewWith(isGroup: true)));

      expect(find.byType(DefaultEmptyRoomState), findsOneWidget);
      expect(
        find.byKey(const Key('chat_empty_room_suggestion_0')),
        findsNothing,
      );
    });
  });

  group('NomaChatView builder passthrough', () {
    late MockChatClient mockClient;
    late ChatUiAdapter adapter;
    const currentUser = ChatUser(id: 'u1', displayName: 'Me');

    setUp(() {
      mockClient = MockChatClient(currentUserId: 'u1');
      adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Alice'),
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await mockClient.dispose();
    });

    Future<ChatViewBuilders> resolved(
      WidgetTester tester,
      ChatViewBuilders? builders,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: builders,
          ),
        ),
      );
      await tester.pump();
      return tester.widget<ChatView>(find.byType(ChatView)).builders;
    }

    testWidgets('forwards the host slots it used to drop', (tester) async {
      Widget? empty(BuildContext context, EmptyRoomInfo room) => null;
      Widget blocked(BuildContext context, ChatMessage message) =>
          const SizedBox.shrink();

      final builders = await resolved(
        tester,
        ChatViewBuilders(
          emptyRoomBuilder: empty,
          blockedMessageBuilder: blocked,
        ),
      );

      expect(builders.emptyRoomBuilder, same(empty));
      expect(builders.blockedMessageBuilder, same(blocked));
    });

    testWidgets('a host that wires nothing keeps the adapter defaults', (
      tester,
    ) async {
      final builders = await resolved(tester, null);

      expect(builders.emptyRoomBuilder, isNull);
      expect(builders.blockedMessageBuilder, isNull);
      expect(builders.attachmentUrlResolver, isNotNull);
      expect(builders.userFetcher, isNotNull);
    });
  });
}
