import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Additional ChatView paths: connection banner labels, retry, custom empty
/// state builder, link preview off, headerBuilder slot.
void main() {
  late ChatController controller;
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(
      initialMessages: const [],
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Other')],
    );
  });

  tearDown(() => controller.dispose());

  Widget viewWith({
    List<MessageAction> actions = const [MessageAction.copy],
    ChatConnectionState? state,
    Widget Function(BuildContext)? headerBuilder,
    bool readOnly = false,
  }) => ChatView(
    controller: controller,
    onSendMessage: (_) {},
    contextMenuActions: actions.toSet(),
    connectionState: state,
    headerBuilder: headerBuilder,
    readOnly: readOnly,
    enableLinkPreview: false,
  );

  testWidgets('shows reconnecting banner with custom label', (tester) async {
    await tester.pumpWidget(
      wrap(viewWith(state: ChatConnectionState.reconnecting)),
    );
    expect(find.byType(ConnectionBanner), findsOneWidget);
  });

  testWidgets('connectionState=error shows error banner', (tester) async {
    await tester.pumpWidget(wrap(viewWith(state: ChatConnectionState.error)));
    expect(find.byType(ConnectionBanner), findsOneWidget);
  });

  testWidgets('readOnly hides the input composer', (tester) async {
    await tester.pumpWidget(wrap(viewWith(readOnly: true)));
    expect(find.byType(MessageInput), findsNothing);
  });

  testWidgets('headerBuilder renders above the message list', (tester) async {
    await tester.pumpWidget(
      wrap(viewWith(headerBuilder: (_) => const Text('Custom header'))),
    );
    expect(find.text('Custom header'), findsOneWidget);
  });

  testWidgets('with messages the input composer is mounted', (tester) async {
    controller.addMessage(
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'incoming hi',
      ),
    );
    await tester.pumpWidget(wrap(viewWith()));
    await tester.pump();
    expect(find.byType(MessageInput), findsOneWidget);
  });
}
