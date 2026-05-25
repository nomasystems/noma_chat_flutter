import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Renders [MessageInput] (the composer) and drives the text → send path.
/// `enableLinkPreview: false` keeps the Dio-backed preview fetcher out of
/// the test; voice recording is never started, so no audio plugin is
/// instantiated (the controller only holds a factory).
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
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Widget composer({void Function(SendMessageRequest request)? onSend}) =>
      MaterialApp(
        home: Scaffold(
          body: MessageInput(
            controller: adapter.getChatController('r1'),
            enableLinkPreview: false,
            onSendMessageRequest: onSend,
          ),
        ),
      );

  testWidgets('renders a text field and the attach affordance', (tester) async {
    await tester.pumpWidget(composer());
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
  });

  testWidgets('typing reveals the send button and dispatches the request', (
    tester,
  ) async {
    SendMessageRequest? sent;
    await tester.pumpWidget(composer(onSend: (r) => sent = r));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.pump();

    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, isNotNull);
    expect(sent!.text, 'hello there');
  });

  testWidgets('empty composer does not show the send button', (tester) async {
    await tester.pumpWidget(composer());
    await tester.pump();

    expect(find.byIcon(Icons.send), findsNothing);
  });
}
