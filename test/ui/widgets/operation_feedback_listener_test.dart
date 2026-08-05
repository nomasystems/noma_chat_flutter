import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final l10n = ChatTheme.defaults.l10n;

  late StreamController<OperationSuccess> successes;
  late StreamController<OperationError> errors;

  setUp(() {
    successes = StreamController<OperationSuccess>.broadcast();
    errors = StreamController<OperationError>.broadcast();
  });

  tearDown(() async {
    await successes.close();
    await errors.close();
  });

  Widget wrap({
    bool enabled = true,
    OperationSuccessLabelBuilder? labelBuilder,
    Stream<OperationError>? errorStream,
  }) => MaterialApp(
    home: Scaffold(
      body: OperationFeedbackListener(
        successes: successes.stream,
        errors: errorStream,
        enabled: enabled,
        labelBuilder: labelBuilder,
        child: const Text('child'),
      ),
    ),
  );

  // Two pumps: one to deliver the stream event, one to show the snackbar.
  Future<void> settleEvent(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('OperationFeedbackListener — successes', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('shows the pinned label on a pin success', (tester) async {
      await tester.pumpWidget(wrap());

      successes.add(const OperationSuccess(kind: OperationKind.pinMessage));
      await settleEvent(tester);

      expect(find.text(l10n.feedbackMessagePinned), findsOneWidget);
    });

    testWidgets('shows the deleted label on a delete success', (tester) async {
      await tester.pumpWidget(wrap());

      successes.add(const OperationSuccess(kind: OperationKind.deleteMessage));
      await settleEvent(tester);

      expect(find.text(l10n.feedbackMessageDeleted), findsOneWidget);
    });

    testWidgets('forward success uses the count carried in messageId', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());

      successes.add(
        const OperationSuccess(
          kind: OperationKind.forwardMessage,
          messageId: '3',
        ),
      );
      await settleEvent(tester);

      expect(find.text(l10n.feedbackForwarded(3)), findsOneWidget);
    });

    testWidgets('unknown kinds produce no snackbar', (tester) async {
      await tester.pumpWidget(wrap());

      successes.add(const OperationSuccess(kind: OperationKind.muteRoom));
      await settleEvent(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a disabled listener ignores events', (tester) async {
      await tester.pumpWidget(wrap(enabled: false));

      successes.add(const OperationSuccess(kind: OperationKind.pinMessage));
      await settleEvent(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a custom labelBuilder overrides the text', (tester) async {
      await tester.pumpWidget(
        wrap(labelBuilder: (_, __, ___) => 'Custom feedback'),
      );

      successes.add(const OperationSuccess(kind: OperationKind.pinMessage));
      await settleEvent(tester);

      expect(find.text('Custom feedback'), findsOneWidget);
    });
  });

  group('OperationFeedbackListener — errors', () {
    testWidgets('content-filter failures surface a moderation snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(errorStream: errors.stream));

      errors.add(
        const OperationError(
          kind: OperationKind.sendMessage,
          failure: ContentFilterFailure(),
        ),
      );
      await settleEvent(tester);

      expect(find.text(l10n.messageBlockedByModeration), findsOneWidget);
    });

    testWidgets('non-moderation failures stay silent by default', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(errorStream: errors.stream));

      errors.add(
        const OperationError(
          kind: OperationKind.sendMessage,
          failure: NetworkFailure(),
        ),
      );
      await settleEvent(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a retry refused because the file was never uploaded '
        'explains itself instead of doing nothing', (tester) async {
      await tester.pumpWidget(wrap(errorStream: errors.stream));

      errors.add(
        const OperationError(
          kind: OperationKind.retrySend,
          failure: ValidationFailure(
            message: 'Attachment was never uploaded; pick the file again',
            errors: {'reason': 'attachment_never_uploaded'},
          ),
        ),
      );
      await settleEvent(tester);

      expect(find.text(l10n.attachmentNeverUploaded), findsOneWidget);
    });

    testWidgets('an unrelated ValidationFailure stays silent', (tester) async {
      await tester.pumpWidget(wrap(errorStream: errors.stream));

      errors.add(
        const OperationError(
          kind: OperationKind.sendMessage,
          failure: ValidationFailure(
            message: 'attachment policy violation: tooLarge',
            errors: {'kind': 'tooLarge'},
          ),
        ),
      );
      await settleEvent(tester);

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('OperationFeedbackListener — coverageAbove', () {
    late OperationFeedbackCoverage seen;

    Widget probe() => Builder(
      builder: (context) {
        seen = OperationFeedbackListener.coverageAbove(context);
        return const Text('probe');
      },
    );

    Future<void> pumpProbe(
      WidgetTester tester, {
      required Widget Function(Widget child) around,
    }) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: around(probe()))),
      );
      await tester.pump();
    }

    testWidgets('reports none with no listener above', (tester) async {
      await pumpProbe(tester, around: (child) => child);

      expect(seen, OperationFeedbackCoverage.none);
    });

    testWidgets('reports successesOnly when the listener above was given no '
        'errors stream — presence alone must not claim failures', (
      tester,
    ) async {
      await pumpProbe(
        tester,
        around: (child) => OperationFeedbackListener(
          successes: successes.stream,
          child: child,
        ),
      );

      expect(seen, OperationFeedbackCoverage.successesOnly);
    });

    testWidgets('reports everything when the listener above covers both', (
      tester,
    ) async {
      await pumpProbe(
        tester,
        around: (child) => OperationFeedbackListener(
          successes: successes.stream,
          errors: errors.stream,
          child: child,
        ),
      );

      expect(seen, OperationFeedbackCoverage.everything);
    });

    testWidgets('a disabled listener claims the subtree outright', (
      tester,
    ) async {
      await pumpProbe(
        tester,
        around: (child) => OperationFeedbackListener(
          successes: successes.stream,
          enabled: false,
          child: child,
        ),
      );

      expect(seen, OperationFeedbackCoverage.everything);
    });

    testWidgets('the nearest listener wins, so a failures-only one nested '
        'under a success-only one reports everything', (tester) async {
      await pumpProbe(
        tester,
        around: (child) => OperationFeedbackListener(
          successes: successes.stream,
          child: OperationFeedbackListener(
            successes: const Stream<OperationSuccess>.empty(),
            errors: errors.stream,
            child: child,
          ),
        ),
      );

      expect(seen, OperationFeedbackCoverage.everything);
    });
  });
}
