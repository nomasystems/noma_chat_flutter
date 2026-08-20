import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// A send that failed exists on this device and nowhere else, so the menu
/// it opens has to say something different: "Delete" would promise a
/// deletion for everyone that has nobody to reach, and the delete window
/// would hide it outright once the row aged, leaving a red bubble the user
/// could not get rid of.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage message({DateTime? at}) => ChatMessage(
    id: 'm1',
    from: 'me',
    text: 'hola',
    timestamp: at ?? DateTime.now(),
  );

  testWidgets('a failed outgoing row offers Discard, not Delete', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageContextMenu(
          message: message(),
          isOutgoing: true,
          isFailed: true,
        ),
      ),
    );

    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a delivered outgoing row still offers Delete and no Discard', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(MessageContextMenu(message: message(), isOutgoing: true)),
    );

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('Discard survives a closed delete window — the window gates a '
      'deletion for everyone, and this row never reached anyone', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageContextMenu(
          message: message(
            at: DateTime.now().subtract(const Duration(days: 5)),
          ),
          isOutgoing: true,
          isFailed: true,
          deleteWindow: const Duration(days: 2),
        ),
      ),
    );

    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('a host that leaves discardFailed out of its action set gets '
      'no Discard row', (tester) async {
    await tester.pumpWidget(
      wrap(
        MessageContextMenu(
          message: message(),
          isOutgoing: true,
          isFailed: true,
          enabledActions: const {MessageAction.reply, MessageAction.copy},
        ),
      ),
    );

    expect(find.text('Discard'), findsNothing);
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('a host whose action set predates Discard keeps its own Delete '
      'on the failed row — the alternative is a bubble with no way out', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageContextMenu(
          message: message(
            at: DateTime.now().subtract(const Duration(days: 5)),
          ),
          isOutgoing: true,
          isFailed: true,
          deleteWindow: const Duration(days: 2),
          enabledActions: const {MessageAction.reply, MessageAction.delete},
        ),
      ),
    );

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });
}
