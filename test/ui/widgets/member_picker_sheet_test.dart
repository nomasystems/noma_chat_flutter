import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The failure path of [MemberPickerSheet]: when the contact list cannot be
/// loaded the sheet must show localized copy, never the raw [ChatFailure]
/// text, which is English and carries the Dart class name.
class _FailingContacts implements ChatContactsApi {
  @override
  Future<ChatResult<ChatPaginatedResponse<ChatContact>>> list({
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async => const ChatFailureResult(ForbiddenFailure());

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

  testWidgets('a failed contact load shows localized copy, never the raw '
      'failure', (tester) async {
    final client = _FakeClient(_FailingContacts());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MemberPickerSheet.show(
                context: context,
                client: client,
                excludeIds: const <String>{},
                onConfirm: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.loadFailed), findsOneWidget);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(contains('Failure')));
    }
  });
}
