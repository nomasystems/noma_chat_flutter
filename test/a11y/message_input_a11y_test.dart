import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

/// Always resolves so the link preview banner appears without waiting on a
/// real network fetch.
class _StubFetcher implements LinkPreviewFetcher {
  @override
  Future<LinkPreviewMetadata?> fetch(String url) async =>
      LinkPreviewMetadata(url: url, title: 'Example');

  @override
  void cancel(String url) {}

  @override
  void cancelAll() {}

  @override
  LinkPreviewCacheStats get cacheStats => const LinkPreviewCacheStats(
    entries: 0,
    capacity: 0,
    failures: 0,
    inFlight: 0,
    hits: 0,
    misses: 0,
    failureRetries: 0,
    evictions: 0,
  );
}

void main() {
  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: const [],
      currentUser: fixtureUserMe,
    );
  });

  tearDown(() => controller.dispose());

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageInput a11y', () {
    testWidgets('attach button exposes Gallery semantic label', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      expect(find.bySemanticsLabel('Gallery'), findsOneWidget);
    });

    testWidgets('attach button tap target is at least 48dp', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      final size = tester.getSize(find.bySemanticsLabel('Gallery'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('camera button exposes Camera semantic label and is 48dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) {},
            onPickCamera: () {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Camera'), findsOneWidget);
      final size = tester.getSize(find.bySemanticsLabel('Camera'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('send button exposes Send semantic label once text is typed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('send button tap target is at least 48dp', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      final size = tester.getSize(find.bySemanticsLabel('Send'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
      'link preview dismiss button exposes a Close semantic label '
      '(regression: was an unlabeled bare GestureDetector)',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageInput(
              controller: controller,
              onSendMessageRequest: (_) {},
              linkPreviewFetcher: _StubFetcher(),
            ),
          ),
        );

        await tester.enterText(
          find.byType(TextField),
          'check https://example.com',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();

        expect(find.bySemanticsLabel('Close'), findsOneWidget);
      },
    );

    testWidgets(
      'cancel-editing button exposes a Close semantic label '
      '(regression: was an unlabeled bare GestureDetector)',
      (tester) async {
        controller.setEditingMessage(fixtureMessage());

        await tester.pumpWidget(
          wrap(
            MessageInput(controller: controller, onSendMessageRequest: (_) {}),
          ),
        );

        expect(find.bySemanticsLabel('Close'), findsOneWidget);
      },
    );
  });
}
