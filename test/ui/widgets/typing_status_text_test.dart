import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final currentUser = const ChatUser(id: 'me', displayName: 'Me', active: true);

  ChatController makeController({List<ChatUser> otherUsers = const []}) =>
      ChatController(
        initialMessages: [],
        currentUser: currentUser,
        otherUsers: otherUsers,
      );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TypingStatusText', () {
    testWidgets('shows nothing when nobody is typing', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows single user typing with resolved name', (tester) async {
      final controller = makeController(
        otherUsers: [
          const ChatUser(id: 'alice', displayName: 'Alice', active: true),
        ],
      );
      controller.setTyping('alice', true);

      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.text('Alice is typing'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows two users typing', (tester) async {
      final controller = makeController(
        otherUsers: [
          const ChatUser(id: 'alice', displayName: 'Alice', active: true),
          const ChatUser(id: 'bob', displayName: 'Bob', active: true),
        ],
      );
      controller.setTyping('alice', true);
      controller.setTyping('bob', true);

      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.text('Alice and Bob are typing'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows count for 3+ users typing', (tester) async {
      final controller = makeController(
        otherUsers: [
          const ChatUser(id: 'alice', displayName: 'Alice', active: true),
          const ChatUser(id: 'bob', displayName: 'Bob', active: true),
          const ChatUser(id: 'carol', displayName: 'Carol', active: true),
        ],
      );
      controller.setTyping('alice', true);
      controller.setTyping('bob', true);
      controller.setTyping('carol', true);

      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.text('3 people are typing'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('falls back to userId when user not in otherUsers', (
      tester,
    ) async {
      final controller = makeController();
      controller.setTyping('unknown-id', true);

      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.text('unknown-id is typing'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('uses Spanish localization', (tester) async {
      final controller = makeController(
        otherUsers: [
          const ChatUser(id: 'alice', displayName: 'Alice', active: true),
        ],
      );
      controller.setTyping('alice', true);

      final theme = ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es);
      await tester.pumpWidget(
        wrap(TypingStatusText(controller: controller, theme: theme)),
      );
      expect(find.textContaining('Alice est'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('disappears when user stops typing', (tester) async {
      final controller = makeController(
        otherUsers: [
          const ChatUser(id: 'alice', displayName: 'Alice', active: true),
        ],
      );
      controller.setTyping('alice', true);

      await tester.pumpWidget(wrap(TypingStatusText(controller: controller)));
      expect(find.text('Alice is typing'), findsOneWidget);

      controller.setTyping('alice', false);
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });
  });
}
