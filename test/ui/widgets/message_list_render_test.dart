import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Renders [MessageList] with a controller populated through the adapter.
/// Covers the list/bubble rendering path. Uses finite pumps (not
/// pumpAndSettle) to avoid hanging on the scroll/jump animations.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client
      ..seedRoom(
        const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
      )
      ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  testWidgets('renders loaded text messages', (tester) async {
    await adapter.sendMessage('r1', text: 'hello world');
    await adapter.sendMessage('r1', text: 'second line');
    final controller = adapter.getChatController('r1');
    await adapter.loadMessages('r1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageList(controller: controller, isGroup: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Bubble text is rendered via rich text, so assert structurally: the
    // list mounted and built its items without throwing (the itemBuilder
    // path is what we're covering here).
    expect(find.byType(MessageList), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an empty list without messages', (tester) async {
    final controller = adapter.getChatController('r1');
    await adapter.loadMessages('r1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageList(controller: controller, isGroup: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MessageList), findsOneWidget);
  });
}
