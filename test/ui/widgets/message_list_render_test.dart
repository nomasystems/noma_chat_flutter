import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  ChatMessage makeMsg(String id, String text, {DateTime? ts}) => ChatMessage(
    id: id,
    from: 'u1',
    text: text,
    timestamp: ts ?? DateTime(2026, 1, 1, 10),
  );

  Widget wrap(ChatController controller) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: MessageList(controller: controller, isGroup: false),
      ),
    ),
  );

  testWidgets('renders the plain text of each loaded message', (tester) async {
    final controller = ChatController(
      initialMessages: [
        makeMsg('1', 'hello world', ts: DateTime(2026, 1, 1, 10)),
        makeMsg('2', 'second line', ts: DateTime(2026, 1, 1, 11)),
      ],
      currentUser: me,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(controller));
    await tester.pump();

    expect(find.textContaining('hello world'), findsOneWidget);
    expect(find.textContaining('second line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders no message bubbles for an empty list', (tester) async {
    final controller = ChatController(initialMessages: [], currentUser: me);
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(controller));
    await tester.pump();

    expect(find.byType(MessageList), findsOneWidget);
    expect(find.textContaining('hello world'), findsNothing);
  });
}
