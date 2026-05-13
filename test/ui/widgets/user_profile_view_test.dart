import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final user = ChatUser(
    id: 'u1',
    displayName: 'Alice Smith',
    bio: 'Software engineer',
  );

  group('UserProfileView', () {
    testWidgets('renders name and bio', (tester) async {
      await tester.pumpWidget(wrap(UserProfileView(user: user)));
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Software engineer'), findsOneWidget);
    });

    testWidgets('calls callbacks when tapped', (tester) async {
      var startChatCalled = false;
      var muteCalled = false;
      var blockCalled = false;

      await tester.pumpWidget(
        wrap(
          UserProfileView(
            user: user,
            onStartChat: () => startChatCalled = true,
            onMute: () => muteCalled = true,
            onBlock: () => blockCalled = true,
          ),
        ),
      );

      await tester.tap(find.text('Start chat'));
      expect(startChatCalled, isTrue);

      await tester.tap(find.text('Mute'));
      expect(muteCalled, isTrue);

      await tester.tap(find.text('Block'));
      expect(blockCalled, isTrue);
    });

    testWidgets('hides buttons when no callback provided', (tester) async {
      await tester.pumpWidget(wrap(UserProfileView(user: user)));
      expect(find.text('Start chat'), findsNothing);
      expect(find.text('Mute'), findsNothing);
      expect(find.text('Block'), findsNothing);
    });
  });
}
