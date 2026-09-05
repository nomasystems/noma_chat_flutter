import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// A user id is an implementation detail. Wherever the SDK has no name for
/// somebody it paints nothing and lets the host put its own placeholder
/// there — it never falls back to spelling the id out.
void main() {
  const nameless = ChatUser(id: '9f2a1c44-0e7b-4d31-9a55-6b0f6f0a1c22');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the mention overlay row is blank, not a uuid', (tester) async {
    await tester.pumpWidget(
      wrap(
        MentionOverlay(query: '', users: const [nameless], onSelect: (_) {}),
      ),
    );

    expect(find.text(nameless.id), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('and a named one still reads its name', (tester) async {
    await tester.pumpWidget(
      wrap(
        MentionOverlay(
          query: '',
          users: const [ChatUser(id: 'u2', displayName: 'Alice')],
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('the profile sheet headline is blank, not a uuid', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const UserProfileView(user: nameless)));

    expect(find.text(nameless.id), findsNothing);
  });

  testWidgets('and a named profile still reads its name', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserProfileView(
          user: ChatUser(id: 'u2', displayName: 'Alice'),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('the member list row is blank, not a uuid', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MemberListView(
          members: [MemberEntry(user: nameless, role: RoomRole.member)],
        ),
      ),
    );

    expect(find.text(nameless.id), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('and a named member still reads its name', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MemberListView(
          members: [
            MemberEntry(
              user: ChatUser(id: 'u2', displayName: 'Alice'),
              role: RoomRole.member,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
  });
}
