import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const l10n = ChatUiLocalizations.en;

  ChatMessage own(Duration age) => ChatMessage(
    id: 'm1',
    from: 'me',
    timestamp: DateTime.now().subtract(age),
    text: 'hi',
  );

  Widget menu(ChatMessage message) => MaterialApp(
    home: Scaffold(
      body: MessageContextMenu(
        message: message,
        isOutgoing: true,
        enabledActions: const {
          MessageAction.copy,
          MessageAction.edit,
          MessageAction.delete,
        },
        editWindow: const Duration(minutes: 15),
        deleteWindow: const Duration(days: 2),
      ),
    ),
  );

  testWidgets('within both windows: edit + delete are shown', (tester) async {
    await tester.pumpWidget(menu(own(const Duration(minutes: 1))));
    expect(find.text(l10n.edit), findsOneWidget);
    expect(find.text(l10n.delete), findsOneWidget);
  });

  testWidgets('past the edit window: edit hidden, delete still shown', (
    tester,
  ) async {
    await tester.pumpWidget(menu(own(const Duration(hours: 1))));
    expect(find.text(l10n.edit), findsNothing);
    expect(find.text(l10n.delete), findsOneWidget);
  });

  testWidgets('past both windows: edit + delete hidden', (tester) async {
    await tester.pumpWidget(menu(own(const Duration(days: 3))));
    expect(find.text(l10n.edit), findsNothing);
    expect(find.text(l10n.delete), findsNothing);
  });

  testWidgets('null windows never hide the actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageContextMenu(
            message: own(const Duration(days: 30)),
            isOutgoing: true,
            enabledActions: const {MessageAction.edit, MessageAction.delete},
          ),
        ),
      ),
    );
    expect(find.text(l10n.edit), findsOneWidget);
    expect(find.text(l10n.delete), findsOneWidget);
  });

  testWidgets('star action renders when enabled (any message)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageContextMenu(
            message: own(const Duration(days: 30)),
            isOutgoing: false,
            enabledActions: const {MessageAction.star, MessageAction.copy},
          ),
        ),
      ),
    );
    expect(find.text(l10n.star), findsOneWidget);
  });
}
