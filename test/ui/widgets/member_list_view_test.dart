import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final members = [
    MemberEntry(
      user: ChatUser(id: 'u1', displayName: 'Alice'),
      role: RoomRole.owner,
    ),
    MemberEntry(
      user: ChatUser(id: 'u2', displayName: 'Bob'),
      role: RoomRole.admin,
    ),
    MemberEntry(
      user: ChatUser(id: 'u3', displayName: 'Charlie'),
      role: RoomRole.member,
    ),
  ];

  group('MemberListView', () {
    testWidgets('renders members with role badges', (tester) async {
      await tester.pumpWidget(wrap(MemberListView(members: members)));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
    });

    testWidgets('shows actions for admin viewing member', (tester) async {
      await tester.pumpWidget(
        wrap(
          MemberListView(
            members: members,
            currentUserRole: RoomRole.admin,
            onRemoveMember: (_) {},
            onChangeRole: (_, __) {},
            onBanMember: (_) {},
          ),
        ),
      );

      // Admin can manage members but not owner or other admins.
      // Charlie (member) should have a popup menu.
      final popups = find.byType(PopupMenuButton<String>);
      expect(popups, findsOneWidget);
    });

    testWidgets('hides actions for regular member', (tester) async {
      await tester.pumpWidget(
        wrap(
          MemberListView(
            members: members,
            currentUserRole: RoomRole.member,
            onRemoveMember: (_) {},
            onChangeRole: (_, __) {},
            onBanMember: (_) {},
          ),
        ),
      );

      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });
  });
}
