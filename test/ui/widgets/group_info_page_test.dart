import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Widget tests for [GroupInfoPage] — the unified WhatsApp-style group
/// detail screen (avatar + name + description + embedded members list +
/// add-members entry point).
///
/// The mock's `rooms.get` always reports the viewer as [RoomRole.owner],
/// so the management affordances (inline edit, add members) are always
/// exercised. Member display names are pre-seeded into the adapter cache
/// so the embedded [GroupMembersView] renders friendly names without
/// firing background `users.get` warm-up calls.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final l10n = ChatTheme.defaults.l10n;

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    // Pre-seed user identities so the embedded members view resolves
    // names from cache (no background warm-up fetches).
    adapter.cacheUsers(const [
      me,
      ChatUser(id: 'u1', displayName: 'Alice'),
      ChatUser(id: 'u2', displayName: 'Bob'),
    ]);
    client
      ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'))
      ..seedUser(const ChatUser(id: 'u2', displayName: 'Bob'));
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  void seedGroup() => client.seedRoom(
    const ChatRoom(
      id: 'r1',
      name: 'My Group',
      subject: 'Hello team',
      members: ['me', 'u1', 'u2'],
    ),
  );

  Widget wrap({String roomId = 'r1'}) => MaterialApp(
    home: GroupInfoPage(adapter: adapter, roomId: roomId),
  );

  group('GroupInfoPage — load + render', () {
    testWidgets('shows a spinner until the room detail resolves', (
      tester,
    ) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      // First frame: detail still loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders title, group name and member count', (tester) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(l10n.groupInfo), findsOneWidget);
      expect(find.text('My Group'), findsOneWidget);
      expect(find.text('${l10n.groupMembers} (3)'), findsOneWidget);
    });

    testWidgets('embedded members list renders the participant names', (
      tester,
    ) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows an error when the room is missing', (tester) async {
      // 'ghost' is never seeded → rooms.get returns NotFoundFailure.
      await tester.pumpWidget(wrap(roomId: 'ghost'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Not found'), findsOneWidget);
    });
  });

  group('GroupInfoPage — owner affordances', () {
    testWidgets('owner sees inline edit buttons and the add-members row', (
      tester,
    ) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // Name + description each expose an edit pencil.
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.text(l10n.addMembers), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    });

    testWidgets('tapping add-members opens the member picker sheet', (
      tester,
    ) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.addMembers));
      await tester.pumpAndSettle();

      // No contacts were seeded, so the opened picker sheet shows its
      // empty state — a marker unique to the sheet (the page row label
      // collides with the sheet title string).
      expect(find.text(l10n.noContactsAvailable), findsOneWidget);
    });
  });

  group('GroupInfoPage — inline editing', () {
    testWidgets('editing the name persists and re-renders', (tester) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // First pencil = name row.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Renamed Group');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('Renamed Group'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('editing the description persists and re-renders', (
      tester,
    ) async {
      seedGroup();

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // Second pencil = description row.
      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New description');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('New description'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
