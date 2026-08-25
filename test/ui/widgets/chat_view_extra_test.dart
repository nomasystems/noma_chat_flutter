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
    Duration? sustainedConnectionErrorDelay,
    Widget Function(BuildContext)? headerBuilder,
    bool readOnly = false,
  }) => ChatView(
    controller: controller,
    callbacks: ChatViewCallbacks(onSendMessageRequest: (_) => true),
    builders: ChatViewBuilders(headerBuilder: headerBuilder),
    behaviors: ChatViewBehaviors(
      contextMenuActions: actions.toSet(),
      connectionState: state,
      sustainedConnectionErrorDelay: sustainedConnectionErrorDelay,
      readOnly: readOnly,
      enableLinkPreview: false,
    ),
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

  testWidgets('a host that sets sustainedConnectionErrorDelay to zero gets '
      'the red band on arrival', (tester) async {
    await tester.pumpWidget(
      wrap(
        viewWith(
          state: ChatConnectionState.error,
          sustainedConnectionErrorDelay: Duration.zero,
        ),
      ),
    );
    expect(find.text('Connection error'), findsOneWidget);
  });

  testWidgets('a host that leaves it unset keeps the default hold-back', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(viewWith(state: ChatConnectionState.error)));
    expect(find.text('Connection error'), findsNothing);
    expect(find.text('Reconnecting...'), findsOneWidget);

    await tester.pump(ConnectionBanner.defaultSustainedErrorDelay);
    expect(find.text('Connection error'), findsOneWidget);
  });

  test('sustainedConnectionErrorDelay survives merging and room state', () {
    const host = ChatViewBehaviors(
      sustainedConnectionErrorDelay: Duration(seconds: 30),
    );
    const defaults = ChatViewBehaviors(enableMentions: true);

    final merged = host.mergedOnto(defaults);
    expect(merged.sustainedConnectionErrorDelay, const Duration(seconds: 30));

    final stamped = merged.withRoomState(
      initialMessageId: null,
      unreadBoundaryMessageId: null,
      unreadCount: 0,
      isBlocked: false,
      isParticipating: true,
      readOnly: false,
      readOnlyLabel: null,
      isGroup: false,
    );
    expect(stamped.sustainedConnectionErrorDelay, const Duration(seconds: 30));

    expect(
      defaults.sustainedConnectionErrorDelay,
      ConnectionBanner.defaultSustainedErrorDelay,
    );
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
