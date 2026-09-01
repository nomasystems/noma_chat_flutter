import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Widget tests for [GroupSetupPage] — the single-page "new group" form.
///
/// The page gathers a name, optional description and a member list, then
/// calls `adapter.rooms.createGroup`. Tests drive it through a
/// [MockChatClient] + real [ChatUiAdapter] and exercise validation, the
/// member chip row, contact suggestions and the create → pop flow.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');
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

  Widget host({List<ChatUser> initialMembers = const <ChatUser>[]}) =>
      MaterialApp(
        home: GroupSetupPage(adapter: adapter, initialMembers: initialMembers),
      );

  IconButton createButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check));

  group('GroupSetupPage — initial render', () {
    testWidgets('renders the title, form fields and member count', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text(l10n.newGroup), findsOneWidget);
      expect(find.text(l10n.groupName), findsOneWidget);
      expect(find.text(l10n.groupDescription), findsOneWidget);
      expect(find.text(l10n.search), findsOneWidget);
      expect(find.text('${l10n.groupMembers} (0)'), findsOneWidget);
    });

    testWidgets('renders initial members as removable rows', (tester) async {
      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('${l10n.groupMembers} (1)'), findsOneWidget);
    });
  });

  group('GroupSetupPage — member chip row', () {
    testWidgets('removing a member drops it from the list and count', (
      tester,
    ) async {
      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('${l10n.groupMembers} (0)'), findsOneWidget);
    });

    testWidgets('seeded contacts appear as tappable suggestions', (
      tester,
    ) async {
      await client.contacts.add('u2');
      adapter.cacheUsers(const [ChatUser(id: 'u2', displayName: 'Bob')]);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Suggestion row with an "add" affordance.
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Bob moved from suggestion (add) to member (close) and the count
      // ticked up.
      expect(find.text('${l10n.groupMembers} (1)'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });
  });

  group('GroupSetupPage — create gating + submission', () {
    testWidgets('create is disabled with no name and no members', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(createButton(tester).onPressed, isNull);
    });

    testWidgets('create enables once name and members are valid', (
      tester,
    ) async {
      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      // Name TextField is the first one in the form.
      await tester.enterText(find.byType(TextField).first, 'Team');
      await tester.pump();

      expect(createButton(tester).onPressed, isNotNull);
    });

    testWidgets('a short name keeps create disabled', (tester) async {
      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ab');
      await tester.pump();

      expect(createButton(tester).onPressed, isNull);
    });

    testWidgets('creating a valid group pops with a GroupCreationResult', (
      tester,
    ) async {
      GroupCreationResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await GroupSetupPage.show(
                    context: context,
                    adapter: adapter,
                    initialMembers: const [alice],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Team');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.roomId, isNotEmpty);
      expect(result!.memberIds, contains('u1'));
    });
  });

  group('GroupSetupPage — member search minimum', () {
    testWidgets('one character says how many are needed instead of falling '
        'back to the contact suggestions', (tester) async {
      await client.contacts.add('u2');
      adapter.cacheUsers(const [ChatUser(id: 'u2', displayName: 'Bob')]);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'b');
      await tester.pumpAndSettle();

      expect(find.text(l10n.searchPromptTooShort(2)), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('the copy names the configured minimum', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupSetupPage(adapter: adapter, minSearchQueryLength: 4),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'bob');
      await tester.pumpAndSettle();

      expect(find.text(l10n.searchPromptTooShort(4)), findsOneWidget);
    });

    testWidgets('clearing the field brings the suggestions back', (
      tester,
    ) async {
      await client.contacts.add('u2');
      adapter.cacheUsers(const [ChatUser(id: 'u2', displayName: 'Bob')]);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'b');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pumpAndSettle();

      expect(find.text(l10n.searchPromptTooShort(2)), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
    });
  });

  group('GroupSetupPage — controls survive their own press', () {
    Finder tooltipOf(Finder icon) => find.ancestor(
      of: icon,
      matching: find.byType(Tooltip, skipOffstage: false),
    );

    testWidgets('removing a member hides its row instead of tearing down the '
        'button that was pressed', (tester) async {
      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      final removeTooltip = tooltipOf(
        find.byIcon(Icons.close, skipOffstage: false),
      );
      final before = tester.state<TooltipState>(removeTooltip);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close, skipOffstage: false), findsOneWidget);
      expect(
        identical(tester.state<TooltipState>(removeTooltip), before),
        isTrue,
      );
    });

    testWidgets('the create button survives its own press while the request '
        'is in flight', (tester) async {
      final slowClient = _SlowRoomsClient(currentUserId: 'me');
      final slowAdapter = ChatUiAdapter(client: slowClient, currentUser: me);
      slowAdapter.start();
      addTearDown(() async {
        await slowAdapter.dispose();
        await slowClient.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => GroupSetupPage.show(
                  context: context,
                  adapter: slowAdapter,
                  initialMembers: const [alice],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Team');
      await tester.pump();

      final createTooltip = tooltipOf(
        find.byIcon(Icons.check, skipOffstage: false),
      );
      final before = tester.state<TooltipState>(createTooltip);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.check, skipOffstage: false), findsOneWidget);
      expect(
        identical(tester.state<TooltipState>(createTooltip), before),
        isTrue,
      );

      await tester.pumpAndSettle();
    });

    testWidgets('re-adding a dropped member reuses its hidden row', (
      tester,
    ) async {
      await client.contacts.add('u1');
      adapter.cacheUsers(const [alice]);

      await tester.pumpWidget(host(initialMembers: const [alice]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('${l10n.groupMembers} (0)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('${l10n.groupMembers} (1)'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.close, skipOffstage: false), findsOneWidget);
    });
  });
}

/// A [MockRoomsApi] whose `create` only completes after a delay, so the
/// page renders at least one frame in its in-flight state.
class _SlowRoomsApi extends MockRoomsApi {
  _SlowRoomsApi(super.client);

  @override
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.create(
      audience: audience,
      allowInvitations: allowInvitations,
      name: name,
      subject: subject,
      members: members,
      avatarUrl: avatarUrl,
      custom: custom,
      forceGroup: forceGroup,
    );
  }
}

class _SlowRoomsClient extends MockChatClient {
  _SlowRoomsClient({required super.currentUserId});

  _SlowRoomsApi? _slowRooms;

  @override
  MockRoomsApi get rooms => _slowRooms ??= _SlowRoomsApi(this);
}
