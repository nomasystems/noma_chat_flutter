import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

class _PaginatingChatClient implements ChatClient {
  _PaginatingChatClient(this._base, {required List<String> allMemberIds})
    : members = _PaginatingMembersApi(_base.members, allMemberIds);

  final ChatClient _base;

  @override
  final ChatMembersApi members;

  @override
  ChatAuthApi get auth => _base.auth;
  @override
  ChatUsersApi get users => _base.users;
  @override
  ChatRoomsApi get rooms => _base.rooms;
  @override
  ChatMessagesApi get messages => _base.messages;
  @override
  ChatContactsApi get contacts => _base.contacts;
  @override
  ChatPresenceApi get presence => _base.presence;
  @override
  ChatAttachmentsApi get attachments => _base.attachments;
  @override
  Stream<ChatEvent> get events => _base.events;
  @override
  ChatConnectionState get connectionState => _base.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _base.stateChanges;
  @override
  Future<void> connect() => _base.connect();
  @override
  Future<void> disconnect() => _base.disconnect();
  @override
  Future<void> notifyTokenRotated() => _base.notifyTokenRotated();
  @override
  Future<void> refresh() => _base.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _base.refreshRoom(roomId);
  @override
  Future<void> logout() => _base.logout();
  @override
  Future<void> dispose() => _base.dispose();
  @override
  void cancelPendingRequests([String reason = '']) =>
      _base.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _base.onOfflineMessageSent = value;
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _base.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

class _PaginatingMembersApi implements ChatMembersApi {
  _PaginatingMembersApi(this._base, this._allMemberIds);

  final ChatMembersApi _base;
  final List<String> _allMemberIds;
  int listCallCount = 0;
  List<ChatPaginationParams?> receivedPagination = [];

  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
  }) async {
    listCallCount++;
    receivedPagination.add(pagination);
    final offset = pagination?.offset ?? 0;
    final limit = pagination?.limit ?? _allMemberIds.length;
    final page = _allMemberIds.skip(offset).take(limit).toList();
    final users = page
        .map((id) => RoomUser(userId: id, displayName: id))
        .toList();
    return ChatSuccess(
      ChatPaginatedResponse(
        items: users,
        hasMore: offset + page.length < _allMemberIds.length,
        totalCount: _allMemberIds.length,
      ),
    );
  }

  @override
  Future<ChatResult<InviteResult>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    String? token,
  }) => _base.invite(roomId, userIds: userIds, mode: mode, token: token);

  @override
  Future<ChatResult<InviteResult>> joinWithToken(
    String roomId, {
    required String token,
  }) => _base.joinWithToken(roomId, token: token);

  @override
  Future<ChatResult<void>> remove(String roomId, String userId) =>
      _base.remove(roomId, userId);

  @override
  Future<ChatResult<void>> leave(String roomId) => _base.leave(roomId);

  @override
  Future<ChatResult<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => _base.updateRole(roomId, userId, role);

  @override
  Future<ChatResult<void>> ban(
    String roomId,
    String userId, {
    String? reason,
  }) => _base.ban(roomId, userId, reason: reason);

  @override
  Future<ChatResult<void>> unban(String roomId, String userId) =>
      _base.unban(roomId, userId);

  @override
  Future<ChatResult<void>> muteUser(String roomId, String userId) =>
      _base.muteUser(roomId, userId);

  @override
  Future<ChatResult<void>> unmuteUser(String roomId, String userId) =>
      _base.unmuteUser(roomId, userId);
}

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

  group('GroupMembersView — pagination for large groups', () {
    const viewer = ChatUser(id: 'me', displayName: 'Me');
    late MockChatClient baseClient;
    late _PaginatingChatClient pagingClient;
    late _PaginatingMembersApi pagingMembers;
    late ChatUiAdapter pagingAdapter;
    late List<String> allMemberIds;

    Widget wrapPaging(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(height: 2000, child: child),
        ),
      ),
    );

    setUp(() {
      allMemberIds = ['me', for (var i = 0; i < 11; i++) 'u$i'];
      baseClient = MockChatClient(currentUserId: 'me');
      baseClient.seedRoom(
        ChatRoom(id: 'big', name: 'Big Group', members: allMemberIds),
      );
      pagingClient = _PaginatingChatClient(
        baseClient,
        allMemberIds: allMemberIds,
      );
      pagingMembers = pagingClient.members as _PaginatingMembersApi;
      pagingAdapter = ChatUiAdapter(client: pagingClient, currentUser: viewer);
      pagingAdapter.start();
    });

    tearDown(() async {
      await pagingAdapter.dispose();
      await baseClient.dispose();
    });

    testWidgets('requests only pageSize members on first load', (tester) async {
      await tester.pumpWidget(
        wrapPaging(
          GroupMembersView(
            adapter: pagingAdapter,
            roomId: 'big',
            currentUserRole: RoomRole.member,
            pageSize: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pagingMembers.listCallCount, 1);
      expect(pagingMembers.receivedPagination.single?.limit, 5);
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('load-more row fetches the next page in embedded mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapPaging(
          GroupMembersView(
            adapter: pagingAdapter,
            roomId: 'big',
            currentUserRole: RoomRole.member,
            embedded: true,
            pageSize: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(6));
      expect(find.text(ChatTheme.defaults.l10n.loadMore), findsOneWidget);

      await tester.tap(find.text(ChatTheme.defaults.l10n.loadMore));
      await tester.pumpAndSettle();

      expect(pagingMembers.listCallCount, 2);
      expect(pagingMembers.receivedPagination[1]?.offset, 5);
      expect(find.byType(ListTile), findsNWidgets(11));
    });

    testWidgets('load-more row disappears once every member has been fetched', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapPaging(
          GroupMembersView(
            adapter: pagingAdapter,
            roomId: 'big',
            currentUserRole: RoomRole.member,
            embedded: true,
            pageSize: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(9));
      expect(find.text(ChatTheme.defaults.l10n.loadMore), findsOneWidget);

      await tester.tap(find.text(ChatTheme.defaults.l10n.loadMore));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(12));
      expect(find.text(ChatTheme.defaults.l10n.loadMore), findsNothing);
    });

    testWidgets('a small group never shows the load-more row', (tester) async {
      final smallIds = ['me', 'u1', 'u2'];
      final smallClient = MockChatClient(currentUserId: 'me');
      smallClient.seedRoom(
        ChatRoom(id: 'small', name: 'Small Group', members: smallIds),
      );
      final smallPagingClient = _PaginatingChatClient(
        smallClient,
        allMemberIds: smallIds,
      );
      final smallAdapter = ChatUiAdapter(
        client: smallPagingClient,
        currentUser: viewer,
      );
      smallAdapter.start();

      await tester.pumpWidget(
        wrapPaging(
          GroupMembersView(
            adapter: smallAdapter,
            roomId: 'small',
            currentUserRole: RoomRole.member,
            embedded: true,
            pageSize: 50,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text(ChatTheme.defaults.l10n.loadMore), findsNothing);
    });
  });
}
