import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Drives every branch of `_presenceDotColor` + `_presenceText` in
/// `UserProfileView` by rendering the widget once per `PresenceStatus`.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  const user = ChatUser(
    id: 'u1',
    displayName: 'Alice',
    bio: 'hello',
  );

  for (final p in PresenceStatus.values) {
    testWidgets('renders the presence row for $p', (tester) async {
      await tester.pumpWidget(wrap(UserProfileView(
        user: user,
        presence: p,
      )));

      // Each status renders its own label.
      final expected = switch (p) {
        PresenceStatus.available => 'Available',
        PresenceStatus.away => 'Away',
        PresenceStatus.busy => 'Busy',
        PresenceStatus.dnd => 'Do not disturb',
        PresenceStatus.offline => 'Offline',
      };
      expect(find.text(expected), findsOneWidget);
    });
  }

  testWidgets('hides the presence row when presence is null',
      (tester) async {
    await tester.pumpWidget(wrap(const UserProfileView(user: user)));
    expect(find.text('Available'), findsNothing);
    expect(find.text('Offline'), findsNothing);
  });
}
