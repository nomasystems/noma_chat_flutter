import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Every notice the SDK raises used to go straight to
/// `ScaffoldMessenger.of(context).showSnackBar`, which throws whenever any
/// `Scaffold` under the messenger is halfway through its own teardown — a
/// `Scaffold` unregisters in `dispose`, never in `deactivate`. The notice
/// went with the throw, and so did the rest of the caller's work.
void main() {
  testWidgets('a notice reaches the messenger', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showChatNotice(ctx, 'unblock failed');
    await tester.pump();

    expect(find.text('unblock failed'), findsOneWidget);
  });

  testWidgets('the snackBarBuilder shapes the bar the SDK publishes', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showChatNotice(
      ctx,
      'no microphone',
      snackBarBuilder: (context, message) =>
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
    await tester.pump();

    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );
  });

  testWidgets('a notice raised mid-frame survives — it is published once the '
      'frame settled, not thrown away with the dying route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              showChatNotice(context, 'raised while building');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('raised while building'), findsOneWidget);
  });

  testWidgets('a context with no messenger at all is a no-op, not a crash', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );

    showChatNotice(ctx, 'nobody is listening');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('ChatNoticeScope', () {
    testWidgets('a host presenter takes the notice instead of the snackbar', (
      tester,
    ) async {
      final seen = <String>[];
      late BuildContext ctx;
      await tester.pumpWidget(
        ChatNoticeScope(
          presenter: (context, message) {
            seen.add(message);
            return true;
          },
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      showChatNotice(ctx, 'role change refused');
      await tester.pump();

      expect(seen, ['role change refused']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a presenter that declines the notice falls through to the '
        'built-in snackbar', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ChatNoticeScope(
          presenter: (context, message) => false,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      showChatNotice(ctx, 'role change refused');
      await tester.pump();

      expect(find.text('role change refused'), findsOneWidget);
    });
  });
}
