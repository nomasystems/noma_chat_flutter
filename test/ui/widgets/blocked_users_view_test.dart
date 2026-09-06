import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Widget tests for [BlockedUsersView].
///
/// The bundled [MockChatClient] always reports an empty blocked list and
/// treats `unblock` as a no-op, so it can only exercise the empty state.
/// To drive the populated list + unblock confirmation flow we wire a tiny
/// hand-written fake that only implements the two contacts methods the
/// view touches (`listBlocked`, `unblock`); everything else routes through
/// `noSuchMethod` and is never called by the widget.
class _FakeBlockedContacts implements ChatContactsApi {
  _FakeBlockedContacts(this._blocked);

  List<String> _blocked;
  bool listFails = false;
  bool unblockFails = false;
  final List<String> unblocked = <String>[];

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async {
    if (listFails) return const ChatFailureResult(NetworkFailure());
    return ChatSuccess(
      ChatPaginatedResponse(items: List<String>.of(_blocked), hasMore: false),
    );
  }

  @override
  Future<ChatResult<void>> unblock(String userId) async {
    if (unblockFails) return const ChatFailureResult(ForbiddenFailure());
    unblocked.add(userId);
    _blocked = _blocked.where((id) => id != userId).toList();
    return const ChatSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A `GET /blocked` that paginates exactly as the backend does: the default
/// page when the request carries no `limit`, a larger one clamped to the wire
/// ceiling, and an honest `hasMore`. A screen that reads a single response is
/// therefore as truncated here as it would be against a real server.
class _PagingBlockedContacts implements ChatContactsApi {
  _PagingBlockedContacts(this._blocked);

  static const int _defaultLimit = 50;
  static const int _maxLimit = 100;

  List<String> _blocked;

  /// Pagination of every `listBlocked` served, in order.
  final List<ChatPaginationParams?> requests = [];

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async {
    requests.add(pagination);
    final limit = (pagination?.limit ?? _defaultLimit).clamp(1, _maxLimit);
    final start = (pagination?.offset ?? 0).clamp(0, _blocked.length);
    final end = (start + limit).clamp(0, _blocked.length);
    return ChatSuccess(
      ChatPaginatedResponse(
        items: _blocked.sublist(start, end),
        hasMore: end < _blocked.length,
        totalCount: _blocked.length,
      ),
    );
  }

  @override
  Future<ChatResult<void>> unblock(String userId) async {
    _blocked = _blocked.where((id) => id != userId).toList();
    return const ChatSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements ChatClient {
  _FakeClient(this._contacts);

  final ChatContactsApi _contacts;

  @override
  ChatContactsApi get contacts => _contacts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final l10n = ChatTheme.defaults.l10n;

  Widget wrap(ChatClient client, {String? Function(String)? names}) =>
      MaterialApp(
        home: Scaffold(
          body: BlockedUsersView(client: client, displayNameResolver: names),
        ),
      );

  group('BlockedUsersView — list states', () {
    testWidgets('shows the empty message when nobody is blocked', (
      tester,
    ) async {
      final client = _FakeClient(_FakeBlockedContacts(<String>[]));

      await tester.pumpWidget(wrap(client));
      await tester.pumpAndSettle();

      expect(find.text(l10n.blockedUsersEmpty), findsOneWidget);
    });

    testWidgets('shows a spinner before the blocked list resolves', (
      tester,
    ) async {
      final client = _FakeClient(_FakeBlockedContacts(['u1']));

      await tester.pumpWidget(wrap(client));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders one row per blocked user with an unblock button', (
      tester,
    ) async {
      final client = _FakeClient(_FakeBlockedContacts(['u1', 'u2']));

      await tester.pumpWidget(
        wrap(client, names: (id) => const {'u1': 'Alice', 'u2': 'Bob'}[id]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(l10n.unblock), findsNWidgets(2));
    });

    testWidgets('shows an error message when the list load fails', (
      tester,
    ) async {
      final client = _FakeClient(
        _FakeBlockedContacts(['u1'])..listFails = true,
      );

      await tester.pumpWidget(wrap(client));
      await tester.pumpAndSettle();

      // Not the empty state, not a list, not loading → the error branch.
      expect(find.text(l10n.blockedUsersEmpty), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.descendant(of: find.byType(Center), matching: find.byType(Text)),
        findsOneWidget,
      );
    });

    testWidgets('the load error is localized copy, never the raw failure', (
      tester,
    ) async {
      final client = _FakeClient(
        _FakeBlockedContacts(['u1'])..listFails = true,
      );

      await tester.pumpWidget(wrap(client));
      await tester.pumpAndSettle();

      expect(find.text(l10n.loadFailed), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(contains('Failure')));
      }
    });
  });

  group('BlockedUsersView — unblock flow', () {
    testWidgets('confirming unblock calls the client and reloads', (
      tester,
    ) async {
      final contacts = _FakeBlockedContacts(['u1']);
      final client = _FakeClient(contacts);

      await tester.pumpWidget(wrap(client, names: (_) => 'Alice'));
      await tester.pumpAndSettle();

      // Open the row's unblock action → confirmation dialog.
      await tester.tap(find.text(l10n.unblock));
      await tester.pumpAndSettle();

      // Accept button is personalized with the resolved name.
      await tester.tap(find.text(l10n.unblockUserName('Alice')));
      await tester.pumpAndSettle();

      expect(contacts.unblocked, ['u1']);
      expect(find.text(l10n.blockedUsersEmpty), findsOneWidget);
    });

    testWidgets('a failing unblock shows the localized notice, not the raw '
        'failure', (tester) async {
      final contacts = _FakeBlockedContacts(['u1'])..unblockFails = true;
      final client = _FakeClient(contacts);

      await tester.pumpWidget(wrap(client, names: (_) => 'Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.unblock));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.unblockUserName('Alice')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.unblockFailed), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(contains('Failure')));
      }
    });

    testWidgets('cancelling the dialog leaves the user blocked', (
      tester,
    ) async {
      final contacts = _FakeBlockedContacts(['u1']);
      final client = _FakeClient(contacts);

      await tester.pumpWidget(wrap(client, names: (_) => 'Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.unblock));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(contacts.unblocked, isEmpty);
      expect(find.text('Alice'), findsOneWidget);
    });
  });

  group('BlockedUsersView — controls survive their own press', () {
    Finder unblockButtonOf(String name) => find.descendant(
      of: find.ancestor(
        of: find.text(name, skipOffstage: false),
        matching: find.byType(ListTile, skipOffstage: false),
      ),
      matching: find.byType(TextButton, skipOffstage: false),
      skipOffstage: false,
    );

    testWidgets('unblocking hides the row instead of tearing down the button '
        'that was pressed', (tester) async {
      final contacts = _FakeBlockedContacts(['u1', 'u2']);
      final client = _FakeClient(contacts);

      await tester.pumpWidget(
        wrap(client, names: (id) => const {'u1': 'Alice', 'u2': 'Bob'}[id]),
      );
      await tester.pumpAndSettle();

      final before = tester.state<State<ButtonStyleButton>>(
        unblockButtonOf('Alice'),
      );

      await tester.tap(find.text(l10n.unblock).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.unblockUserName('Alice')));
      await tester.pumpAndSettle();

      expect(contacts.unblocked, ['u1']);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Alice', skipOffstage: false), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(
        identical(
          tester.state<State<ButtonStyleButton>>(unblockButtonOf('Alice')),
          before,
        ),
        isTrue,
      );
    });

    testWidgets('unblocking the last row keeps the pressed button mounted '
        'under the empty state', (tester) async {
      final contacts = _FakeBlockedContacts(['u1']);
      final client = _FakeClient(contacts);

      await tester.pumpWidget(wrap(client, names: (_) => 'Alice'));
      await tester.pumpAndSettle();

      final before = tester.state<State<ButtonStyleButton>>(
        unblockButtonOf('Alice'),
      );

      await tester.tap(find.text(l10n.unblock));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.unblockUserName('Alice')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.blockedUsersEmpty), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Alice', skipOffstage: false), findsOneWidget);
      expect(
        identical(
          tester.state<State<ButtonStyleButton>>(unblockButtonOf('Alice')),
          before,
        ),
        isTrue,
      );
    });
  });

  group('BlockedUsersView — paginated backend', () {
    testWidgets('a blocked list longer than one page is shown whole', (
      tester,
    ) async {
      final contacts = _PagingBlockedContacts([
        for (var i = 0; i < 120; i++) 'u$i',
      ]);
      final client = _FakeClient(contacts);

      await tester.pumpWidget(
        wrap(client, names: (id) => 'User ${id.substring(1)}'),
      );
      await tester.pumpAndSettle();

      expect(
        contacts.requests.length,
        2,
        reason: '120 blocked users at the wire maximum of 100 is two reads',
      );
      expect(contacts.requests.first?.limit, 100);
      expect(contacts.requests.first?.offset, 0);
      expect(contacts.requests[1]?.offset, 100);

      // The row past the first backend page exists and is reachable, so
      // the user can still unblock the people the first page left out.
      expect(find.text('User 0'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('User 119'), 400);
      expect(find.text('User 119'), findsOneWidget);
    });

    testWidgets('a page that fails leaves the screen on the error state', (
      tester,
    ) async {
      final contacts = _FakeBlockedContacts(['u1'])..listFails = true;
      final client = _FakeClient(contacts);

      await tester.pumpWidget(wrap(client));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
      expect(find.text(l10n.blockedUsersEmpty), findsNothing);
    });
  });
}
