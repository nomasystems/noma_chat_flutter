import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// An edit refused because its window closed used to be the quietest
/// failure in the chat: the composer shut, the bubble rolled back to the
/// original wording, and nothing said a word — so the user walked away
/// believing they had corrected what they wrote.
void main() {
  final l10n = ChatTheme.defaults.l10n;

  group('the refusal is spoken', () {
    late StreamController<OperationError> errors;

    setUp(() => errors = StreamController<OperationError>.broadcast());
    tearDown(() async => errors.close());

    Widget wrap() => MaterialApp(
      home: Scaffold(
        body: OperationFeedbackListener(
          successes: const Stream<OperationSuccess>.empty(),
          errors: errors.stream,
          child: const Text('child'),
        ),
      ),
    );

    testWidgets('a 403 edit_window_expired surfaces as a snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());

      errors.add(
        const OperationError(
          kind: OperationKind.editMessage,
          failure: EditWindowExpiredFailure(),
          roomId: 'r1',
          messageId: 'm1',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.editWindowExpired), findsOneWidget);
    });

    testWidgets('an ordinary edit failure stays silent — it leaves a '
        'retryable bubble, and a toast would be noise', (tester) async {
      await tester.pumpWidget(wrap());

      errors.add(
        const OperationError(
          kind: OperationKind.editMessage,
          failure: NetworkFailure('offline'),
          roomId: 'r1',
          messageId: 'm1',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the wording is handed back', () {
    testWidgets('re-entering edit mode with a draft seeds the composer with '
        'what was typed, not with what the server still holds', (tester) async {
      final controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'me',
            text: 'original',
            timestamp: DateTime(2026, 1, 1, 10),
          ),
        ],
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageInput(controller: controller)),
        ),
      );

      // The user opens the editor and confirms; the composer closes.
      controller.setEditingMessage(controller.messages.single);
      await tester.pump();
      controller.setEditingMessage(null);
      await tester.pump();

      // The edit is refused, and the attempt comes back with it.
      controller.setEditingMessage(
        controller.messages.single,
        draftText: 'the corrected wording',
      );
      await tester.pump();

      expect(find.text('the corrected wording'), findsOneWidget);
      expect(controller.editingDraftText, 'the corrected wording');
    });

    testWidgets('the ordinary "start editing" path still seeds the message '
        'text', (tester) async {
      final controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'me',
            text: 'original',
            timestamp: DateTime(2026, 1, 1, 10),
          ),
        ],
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageInput(controller: controller)),
        ),
      );

      controller.setEditingMessage(controller.messages.single);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'original'), findsOneWidget);
      expect(controller.editingDraftText, isNull);
    });

    testWidgets('closing the editor clears the draft so the next edit starts '
        'clean', (tester) async {
      final controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'me',
            text: 'original',
            timestamp: DateTime(2026, 1, 1, 10),
          ),
        ],
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      controller.setEditingMessage(
        controller.messages.single,
        draftText: 'attempt',
      );
      controller.setEditingMessage(null);

      expect(controller.editingDraftText, isNull);
    });
  });

  group('the built-in edit callback picks its moment', () {
    const me = ChatUser(id: 'u1', displayName: 'Me');
    late MockChatClient mockClient;
    late ChatUiAdapter adapter;

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

    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'original',
      timestamp: DateTime(2026, 1, 1, 10),
    );

    testWidgets('an expired window hands the wording back to the composer', (
      tester,
    ) async {
      final view = await viewOf(tester);
      mockClient.messages.failNextUpdateWith = const EditWindowExpiredFailure();

      view.callbacks.onEditMessage!(message, 'the corrected wording');
      await tester.pump();
      await tester.pump();

      expect(view.controller.editingMessage?.id, 'm1');
      expect(view.controller.editingDraftText, 'the corrected wording');

      // Seeding the composer starts the typing-indicator debounce; let it
      // run out before the tree comes down.
      view.controller.setEditingMessage(null);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('any other refusal leaves the composer shut — nothing told '
        'the user why it would be reopening', (tester) async {
      final view = await viewOf(tester);
      mockClient.messages.failNextUpdateWith = const NetworkFailure('offline');

      view.callbacks.onEditMessage!(message, 'the corrected wording');
      await tester.pump();
      await tester.pump();

      expect(view.controller.editingMessage, isNull);
      expect(view.controller.editingDraftText, isNull);
    });

    testWidgets('an edit that goes through leaves the composer shut too', (
      tester,
    ) async {
      final view = await viewOf(tester);
      mockClient.addMessage('room1', message);

      view.callbacks.onEditMessage!(message, 'the corrected wording');
      await tester.pump();
      await tester.pump();

      expect(view.controller.editingMessage, isNull);
    });

    testWidgets('a host that opted out keeps its composer shut even on an '
        'expired window', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            behaviors: const ChatViewBehaviors(
              restoreComposerOnEditFailure: false,
            ),
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pump();
      final view = tester.widget<ChatView>(find.byType(ChatView));
      mockClient.messages.failNextUpdateWith = const EditWindowExpiredFailure();

      view.callbacks.onEditMessage!(message, 'the corrected wording');
      await tester.pump();
      await tester.pump();

      expect(view.controller.editingMessage, isNull);
    });
  });
}
