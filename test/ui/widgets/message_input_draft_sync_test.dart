import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    client.seedRoom(
      const ChatRoom(id: 'r2', name: 'Room 2', members: ['me', 'u2']),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Widget composer(ChatController controller) => MaterialApp(
    home: Scaffold(
      body: MessageInput(
        controller: controller,
        enableLinkPreview: false,
        onSendMessageRequest: (_) {},
      ),
    ),
  );

  testWidgets('pre-fills the composer from the controller draft', (
    tester,
  ) async {
    final controller = adapter.getChatController('r1')..setDraft('unsent text');

    await tester.pumpWidget(composer(controller));
    await tester.pump();

    expect(find.text('unsent text'), findsOneWidget);
  });

  testWidgets('saves the typed text back to the controller draft on dispose', (
    tester,
  ) async {
    final controller = adapter.getChatController('r1');

    await tester.pumpWidget(composer(controller));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'half-written reply');
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(controller.draft, 'half-written reply');
  });

  testWidgets('a per-room draft pre-fills only its own composer', (
    tester,
  ) async {
    adapter.getChatController('r1').setDraft('draft for room one');
    adapter.getChatController('r2').setDraft('draft for room two');

    await tester.pumpWidget(composer(adapter.getChatController('r2')));
    await tester.pump();

    expect(find.text('draft for room two'), findsOneWidget);
    expect(find.text('draft for room one'), findsNothing);
  });

  testWidgets('clearing the composer wipes the controller draft on dispose', (
    tester,
  ) async {
    final controller = adapter.getChatController('r1')
      ..setDraft('to be erased');

    await tester.pumpWidget(composer(controller));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(controller.draft, isNull);
  });
}
