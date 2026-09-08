import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Covers the admin-only `PopupMenuButton` branch of `MemberListView`.
/// The basic test file only renders the list; here we open the popup and
/// pick each action to drive the switch arms.
void main() {
  const admin = ChatUser(id: 'admin', displayName: 'Admin');
  const target = ChatUser(id: 'u2', displayName: 'Target');

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('admin can pick Remove / Change role / Ban from the menu', (
    tester,
  ) async {
    ChatUser? removed;
    ChatUser? rotated;
    RoomRole? newRole;
    ChatUser? banned;

    await tester.pumpWidget(
      wrap(
        MemberListView(
          members: const [
            MemberEntry(user: admin, role: RoomRole.owner),
            MemberEntry(user: target, role: RoomRole.member),
          ],
          currentUserRole: RoomRole.owner,
          onRemoveMember: (u) => removed = u,
          onChangeRole: (u, r) {
            rotated = u;
            newRole = r;
          },
          onBanMember: (u) => banned = u,
        ),
      ),
    );

    // Open the popup for the manageable member.
    final menu = find.byType(PopupMenuButton<String>);
    expect(menu, findsOneWidget); // only target is manageable; owner is not
    await tester.tap(menu);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();
    expect(removed, isNotNull);

    // Reopen and pick Change role.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();
    expect(rotated, isNotNull);
    expect(newRole, RoomRole.admin);

    // Reopen and pick Ban.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ban'));
    await tester.pumpAndSettle();
    expect(banned, isNotNull);
  });

  testWidgets('members cannot manage anyone (no popup rendered)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MemberListView(
          members: const [
            MemberEntry(user: admin, role: RoomRole.owner),
            MemberEntry(user: target, role: RoomRole.member),
          ],
          currentUserRole: RoomRole.member,
          onRemoveMember: (_) {},
          onChangeRole: (_, __) {},
          onBanMember: (_) {},
        ),
      ),
    );

    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('admin promoting an admin downgrades them to member', (
    tester,
  ) async {
    RoomRole? newRole;

    const otherAdmin = ChatUser(id: 'admin2', displayName: 'AdminTwo');

    await tester.pumpWidget(
      wrap(
        MemberListView(
          members: const [
            MemberEntry(user: admin, role: RoomRole.owner),
            MemberEntry(user: otherAdmin, role: RoomRole.admin),
          ],
          currentUserRole: RoomRole.owner,
          onChangeRole: (u, r) => newRole = r,
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();

    expect(newRole, RoomRole.member);
  });

  testWidgets('removing a member hides its row instead of tearing down the '
      'menu that was pressed', (tester) async {
    Finder menuTooltipOf(String userId) => find.descendant(
      of: find.byKey(ValueKey(userId), skipOffstage: false),
      matching: find.byType(Tooltip, skipOffstage: false),
      skipOffstage: false,
    );

    await tester.pumpWidget(const _RemovableMemberList());
    await tester.pumpAndSettle();

    final before = tester.state<TooltipState>(menuTooltipOf('u2'));

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();

    expect(find.text('Target'), findsNothing);
    expect(find.text('Target', skipOffstage: false), findsOneWidget);
    expect(
      identical(tester.state<TooltipState>(menuTooltipOf('u2')), before),
      isTrue,
    );
  });
}

/// Host that owns the roster so "remove" really drops the row, the way a
/// consumer of [MemberListView] wires it.
class _RemovableMemberList extends StatefulWidget {
  const _RemovableMemberList();

  @override
  State<_RemovableMemberList> createState() => _RemovableMemberListState();
}

class _RemovableMemberListState extends State<_RemovableMemberList> {
  List<MemberEntry> _members = const [
    MemberEntry(
      user: ChatUser(id: 'u2', displayName: 'Target'),
      role: RoomRole.member,
    ),
    MemberEntry(
      user: ChatUser(id: 'u3', displayName: 'Other'),
      role: RoomRole.member,
    ),
  ];

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: MemberListView(
        members: _members,
        currentUserRole: RoomRole.owner,
        onRemoveMember: (user) => setState(() {
          _members = _members
              .where((e) => e.user.id != user.id)
              .toList(growable: false);
        }),
      ),
    ),
  );
}
