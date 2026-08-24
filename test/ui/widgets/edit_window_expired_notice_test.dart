import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/exception_mapper.dart';

/// An edit refused because its window closed is the one failure with no
/// bubble to fall back on: the row rolls back to the original wording, so
/// nothing on screen separates a refused edit from an applied one. The
/// notice is all the user gets, and it has to survive the whole way down.
///
/// The body here is the one `chat_api` really answers with —
/// `chat_api_cb_messages.erl` builds it as
/// `forbidden(<<"edit window expired">>, edit_window_expired)`, and a
/// server that predates the token sends the prose alone.
const _serverBody = <String, dynamic>{
  'code': 403,
  'detail': 'edit window expired',
};

void main() {
  final l10n = ChatTheme.defaults.l10n;

  testWidgets('the 403 the server really sends is spoken, token or no token', (
    tester,
  ) async {
    final failure = mapExceptionToFailure(
      const ChatForbiddenException(body: _serverBody),
    );
    expect(failure, isA<EditWindowExpiredFailure>());

    final errors = StreamController<OperationError>.broadcast();
    addTearDown(errors.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationFeedbackListener(
            successes: const Stream<OperationSuccess>.empty(),
            errors: errors.stream,
            child: const Text('child'),
          ),
        ),
      ),
    );

    errors.add(
      OperationError(
        kind: OperationKind.editMessage,
        failure: failure,
        roomId: 'r1',
        messageId: 'm1',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.editWindowExpired), findsOneWidget);
  });

  testWidgets('the same body with the token still lands on the typed failure', (
    tester,
  ) async {
    final failure = mapExceptionToFailure(
      const ChatForbiddenException(
        body: <String, dynamic>{..._serverBody, 'error': 'edit_window_expired'},
        errorToken: 'edit_window_expired',
      ),
    );

    expect(failure, isA<EditWindowExpiredFailure>());
  });

  test('a 403 whose prose means something else stays generic', () {
    expect(
      mapExceptionToFailure(
        const ChatForbiddenException(
          body: <String, dynamic>{'code': 403, 'detail': 'You are not a member'},
        ),
      ),
      isA<ForbiddenFailure>(),
    );
  });

  test('the delete window gets the same reading of its prose', () {
    expect(
      mapExceptionToFailure(
        const ChatForbiddenException(
          body: <String, dynamic>{
            'code': 403,
            'detail': 'delete window expired',
          },
        ),
      ),
      isA<DeleteWindowExpiredFailure>(),
    );
  });

  testWidgets('a notice raised on a context that has already gone still '
      'reaches the screen', (tester) async {
    late BuildContext raiser;
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              raiser = context;
              messenger = ScaffoldMessenger.of(context);
              return const Text('child');
            },
          ),
        ),
      ),
    );

    // The subtree that asked for the edit is gone by the time the server
    // answers — every ancestor lookup on its context now throws instead of
    // answering null, which used to take the notice down with it.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
    );
    expect(() => ChatNoticeScope.maybeOf(raiser), throwsFlutterError);
    expect(() => ScaffoldMessenger.maybeOf(raiser), throwsFlutterError);

    showChatNotice(raiser, l10n.editWindowExpired, messenger: messenger);
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.editWindowExpired), findsOneWidget);
  });

  testWidgets('a host presenter kept from before takes the notice when the '
      'context can no longer be asked for one', (tester) async {
    late BuildContext raiser;
    final presented = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ChatNoticeScope(
          presenter: (context, message) {
            presented.add(message);
            return true;
          },
          child: Scaffold(
            body: Builder(
              builder: (context) {
                raiser = context;
                return const Text('child');
              },
            ),
          ),
        ),
      ),
    );
    final presenter = ChatNoticeScope.maybeOf(raiser);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
    );

    showChatNotice(raiser, l10n.editWindowExpired, presenter: presenter);
    await tester.pump();

    expect(presented, [l10n.editWindowExpired]);
    expect(find.byType(SnackBar), findsNothing);
  });
}
