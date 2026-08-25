import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// What the composer does with the wording when the host refuses the send.
///
/// The refusals modelled here are the real ones: a host that answers after
/// an await — a contact gate asking the backend whether the peer still
/// takes content — and answers "no". Nothing was created anywhere, so the
/// text the user typed only exists in the field they typed it in.
void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Alice');

  // The wording QA had in the field when the send was refused.
  const draft =
      'Borrador largo que no quiero perder porque me ha costado escribirlo 1705';

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(initialMessages: [], currentUser: user);
  });

  tearDown(() => controller.dispose());

  group('MessageInput with a refused send', () {
    testWidgets('keeps the typed text in the composer', (tester) async {
      final refused = <String>[];
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (req) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              refused.add(req.text);
              return false;
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(refused, [draft]);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, draft);
      expect(find.text(draft), findsOneWidget);
      expect(controller.draft, draft);
    });

    testWidgets('puts the message being replied to back under it', (
      tester,
    ) async {
      final quoted = ChatMessage(
        id: 'm1',
        from: 'u2',
        text: 'Nos vemos a las 20:00',
        timestamp: DateTime(2026, 8, 24, 19, 30),
      );
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) async => false,
          ),
        ),
      );

      controller.setReplyTo(quoted);
      await tester.pump();
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, draft);
      expect(controller.replyingTo?.id, 'm1');
    });

    testWidgets('reopens edit mode holding what was typed', (tester) async {
      final edited = ChatMessage(
        id: 'm2',
        from: 'u1',
        text: 'Wording the server still holds',
        timestamp: DateTime(2026, 8, 24, 19, 30),
      );
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) async => false,
          ),
        ),
      );

      controller.setEditingMessage(edited);
      await tester.pump();
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.editingMessage?.id, 'm2');
      expect(controller.editingDraftText, draft);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, draft);
    });

    testWidgets('does not overwrite what was typed while it resolved', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return false;
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'lo siguiente que escribo',
      );
      await tester.pump(const Duration(milliseconds: 50));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'lo siguiente que escribo');
      expect(find.text(draft), findsNothing);
    });
  });

  group('MessageInput with a refused edit', () {
    final edited = ChatMessage(
      id: 'm4',
      from: 'u1',
      text: 'Wording the server still holds',
      timestamp: DateTime(2026, 8, 24, 19, 30),
    );

    testWidgets('reopens edit mode holding what was typed', (tester) async {
      final refused = <String>[];
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
            onEditMessage: (msg, text) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              refused.add(text);
              return false;
            },
          ),
        ),
      );

      controller.setEditingMessage(edited);
      await tester.pump();
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(refused, [draft]);
      expect(controller.editingMessage?.id, 'm4');
      expect(controller.editingDraftText, draft);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, draft);
    });

    testWidgets('an accepted edit closes the composer', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
            onEditMessage: (_, _) async => true,
          ),
        ),
      );

      controller.setEditingMessage(edited);
      await tester.pump();
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.editingMessage, isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });
  });

  group('the built-in edit callback answers the composer', () {
    const me = ChatUser(id: 'u1', displayName: 'Alice');
    late MockChatClient mockClient;
    late ChatUiAdapter adapter;

    final message = ChatMessage(
      id: 'm5',
      from: 'u1',
      text: 'original',
      timestamp: DateTime(2026, 8, 24, 19, 30),
    );

    setUp(() {
      mockClient = MockChatClient(currentUserId: 'u1');
      mockClient.seedRoom(
        const ChatRoom(id: 'room1', name: 'Team', members: ['u1', 'u2']),
      );
      adapter = ChatUiAdapter(client: mockClient, currentUser: me);
    });

    tearDown(() async {
      await adapter.dispose();
      await mockClient.dispose();
    });

    Future<ChatView> viewOf(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pump();
      return tester.widget<ChatView>(find.byType(ChatView));
    }

    testWidgets('a closed door hands the wording back and refuses', (
      tester,
    ) async {
      final view = await viewOf(tester);
      mockClient.messages.failNextUpdateWith = const ForbiddenFailure(
        statusCode: 403,
      );

      final taken = await view.callbacks.onEditMessage!(message, draft);
      await tester.pump();

      expect(taken, isFalse);
      expect(view.controller.editingMessage?.id, 'm5');
      expect(view.controller.editingDraftText, draft);

      view.controller.setEditingMessage(null);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a failure on the wire leaves the composer shut', (
      tester,
    ) async {
      final view = await viewOf(tester);
      mockClient.messages.failNextUpdateWith = const NetworkFailure('offline');

      final taken = await view.callbacks.onEditMessage!(message, draft);
      await tester.pump();

      expect(taken, isTrue);
      expect(view.controller.editingMessage, isNull);
      expect(view.controller.editingDraftText, isNull);
    });
  });

  group('MessageInput with an accepted send', () {
    testWidgets('still clears the composer and the stored draft', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return true;
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(controller.draft, isNull);

      // A sent message does not come back through the draft: any later
      // notification from the controller must leave the field empty.
      controller.addMessage(
        ChatMessage(
          id: 'm3',
          from: 'u2',
          text: 'ok',
          timestamp: DateTime(2026, 8, 24, 19, 35),
        ),
      );
      await tester.pump();
      final after = tester.widget<TextField>(find.byType(TextField));
      expect(after.controller!.text, isEmpty);
    });
  });

  group('the composer the host really mounts', () {
    late MockChatClient mockClient;
    late ChatUiAdapter adapter;

    setUp(() {
      mockClient = MockChatClient(currentUserId: 'u1');
      mockClient.seedRoom(
        const ChatRoom(id: 'room1', name: 'Alice', members: ['u1', 'u2']),
      );
      adapter = ChatUiAdapter(client: mockClient, currentUser: user);
    });

    tearDown(() async {
      await adapter.dispose();
      await mockClient.dispose();
    });

    testWidgets('a refusal that comes back through NomaChatView keeps it', (
      tester,
    ) async {
      final refused = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            callbacks: ChatViewCallbacks(
              onSendMessageRequest: (request) async {
                refused.add(request.text);
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(refused, [draft]);
      expect(find.byType(MessageInput), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, draft);
      expect(
        tester.widget<ChatView>(find.byType(ChatView)).controller.draft,
        draft,
      );

      await tester.pump(const Duration(seconds: 2));
    });
  });
}
