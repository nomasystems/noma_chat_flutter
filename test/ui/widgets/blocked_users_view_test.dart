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
    unblocked.add(userId);
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
}
