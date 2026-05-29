import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Widget tests for [GroupMembersView].
///
/// The view loads its member list through the SDK adapter, so each test
/// wires a [MockChatClient] + real [ChatUiAdapter] and seeds the room the
/// view fetches. Member roles always come back as [RoomRole.member] from
/// the mock, so role-badge assertions are driven through
/// `currentUserRole` (the viewer's role) instead.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final l10n = ChatTheme.defaults.l10n;

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  String? names(String id) =>
      const {'me': 'Me', 'u1': 'Alice', 'u2': 'Bob'}[id];

  GroupMembersView view({
    String roomId = 'r1',
    RoomRole currentUserRole = RoomRole.member,
    bool embedded = false,
    void Function(String userId)? onMessageMember,
  }) => GroupMembersView(
    adapter: adapter,
    roomId: roomId,
    currentUserRole: currentUserRole,
    displayNameResolver: names,
    embedded: embedded,
    onMessageMember: onMessageMember,
  );

  group('GroupMembersView — load + render', () {
    testWidgets('renders one row per member with resolved names', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1', 'u2']),
      );

      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('renders an empty list for a room with no members', (
      tester,
    ) async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'G', members: []));

      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows an error message when the room cannot be loaded', (
      tester,
    ) async {
      // 'missing' is never seeded → members.list returns NotFoundFailure.
      await tester.pumpWidget(wrap(view(roomId: 'missing')));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.descendant(of: find.byType(Center), matching: find.byType(Text)),
        findsOneWidget,
      );
    });
  });

  group('GroupMembersView — management affordances', () {
    testWidgets('admin viewer gets a manage button for other members', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view(currentUserRole: RoomRole.admin)));
      await tester.pumpAndSettle();

      // Self row (me) is never actionable → exactly one manage button (u1).
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('plain member viewer sees no manage buttons', (tester) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view(currentUserRole: RoomRole.member)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('opening the manage menu surfaces the make-admin action', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view(currentUserRole: RoomRole.admin)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text(l10n.makeAdmin), findsOneWidget);
      expect(find.text(l10n.removeMember), findsOneWidget);
    });

    testWidgets('tapping make-admin runs the role update without crashing', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view(currentUserRole: RoomRole.admin)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.makeAdmin));
      await tester.pumpAndSettle();

      // Sheet dismissed, list reloaded, row still present.
      expect(find.text(l10n.makeAdmin), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
    });
  });

  group('GroupMembersView — interaction + layout modes', () {
    testWidgets('tapping a non-self row invokes onMessageMember', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );
      String? tapped;

      await tester.pumpWidget(wrap(view(onMessageMember: (id) => tapped = id)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(tapped, 'u1');
    });

    testWidgets('self row never invokes onMessageMember', (tester) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );
      String? tapped;

      await tester.pumpWidget(wrap(view(onMessageMember: (id) => tapped = id)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Me'));
      await tester.pump();

      expect(tapped, isNull);
    });

    testWidgets('non-embedded mode wraps the list in a RefreshIndicator', (
      tester,
    ) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('embedded mode drops the RefreshIndicator', (tester) async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'G', members: ['me', 'u1']),
      );

      await tester.pumpWidget(wrap(view(embedded: true)));
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  });
}
