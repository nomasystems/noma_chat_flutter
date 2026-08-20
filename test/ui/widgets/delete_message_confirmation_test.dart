import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Deleting a message is the one action in the chat that reaches other
/// people and cannot be taken back, and the gesture that starts it is a
/// long press anywhere on the row. It used to fire on the first tap of
/// "Delete", with no dialog and no undo — while blocking a contact and
/// clearing a chat, both recoverable, each asked first.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  final l10n = ChatTheme.defaults.l10n;

  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    mockClient.seedRoom(
      const ChatRoom(id: 'room1', name: 'Team', members: ['u1', 'u2']),
    );
    adapter = ChatUiAdapter(client: mockClient, currentUser: me);
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'room1', name: 'Team', isGroup: true),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  Future<ChatViewCallbacks> callbacksOf(
    WidgetTester tester, {
    ChatViewBehaviors? behaviors,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'room1',
          adapter: adapter,
          behaviors: behaviors,
          hydrateGroupMembers: false,
        ),
      ),
    );
    await tester.pump();
    return tester.widget<ChatView>(find.byType(ChatView)).callbacks;
  }

  testWidgets('the built-in delete asks before it reaches anyone', (
    tester,
  ) async {
    final callbacks = await callbacksOf(tester);
    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'hola',
      timestamp: DateTime(2026, 1, 1),
    );
    mockClient.addMessage('room1', message);

    callbacks.onDeleteMessage!(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.deleteMessageConfirmTitle), findsOneWidget);
    expect(find.text(l10n.deleteMessageConfirmBody), findsOneWidget);

    // Backing out leaves the message where it was.
    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.deleteMessageConfirmTitle), findsNothing);
    expect((await mockClient.messages.get('room1', 'm1')).isSuccess, isTrue);
  });

  testWidgets('confirming goes through to the delete', (tester) async {
    final callbacks = await callbacksOf(tester);
    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'hola',
      timestamp: DateTime(2026, 1, 1),
    );
    mockClient.addMessage('room1', message);

    callbacks.onDeleteMessage!(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(l10n.delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.deleteMessageConfirmTitle), findsNothing);
    // The dialog closing proves nothing on its own: what the confirmation
    // gates is the delete itself reaching the room.
    expect((await mockClient.messages.get('room1', 'm1')).isFailure, isTrue);
  });

  testWidgets('a host that runs its own confirmation can turn this one off', (
    tester,
  ) async {
    final callbacks = await callbacksOf(
      tester,
      behaviors: const ChatViewBehaviors(confirmDeleteForEveryone: false),
    );
    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'hola',
      timestamp: DateTime(2026, 1, 1),
    );
    mockClient.addMessage('room1', message);

    callbacks.onDeleteMessage!(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.deleteMessageConfirmTitle), findsNothing);
    expect((await mockClient.messages.get('room1', 'm1')).isFailure, isTrue);
  });

  testWidgets('a failed row that reaches the delete callback is discarded, '
      'not deleted — the server never saw it', (tester) async {
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
    final view = tester.widget<ChatView>(find.byType(ChatView));
    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'hola',
      timestamp: DateTime(2026, 1, 1),
    );
    mockClient.addMessage('room1', message);
    view.controller.addMessage(message);
    view.controller.markFailed('m1');

    view.callbacks.onDeleteMessage!(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.deleteMessageConfirmTitle), findsNothing);
    expect(view.controller.messages.any((m) => m.id == 'm1'), isFalse);
    // Nothing was asked of the server: a delete of a message it never
    // received would have failed and left the bubble where it was.
    expect((await mockClient.messages.get('room1', 'm1')).isSuccess, isTrue);
  });

  testWidgets('discarding a failed send is not gated — it never left this '
      'device', (tester) async {
    final callbacks = await callbacksOf(tester);
    expect(callbacks.onDiscardFailedMessage, isNotNull);

    final message = ChatMessage(
      id: 'm1',
      from: 'u1',
      text: 'hola',
      timestamp: DateTime(2026, 1, 1),
    );
    callbacks.onDiscardFailedMessage!(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.deleteMessageConfirmTitle), findsNothing);
  });
}
