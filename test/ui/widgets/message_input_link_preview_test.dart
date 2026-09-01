import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Drives the `MessageInput` link-preview pipeline using a fake fetcher,
/// hitting the debounce + state-transition branches that the broader
/// `message_input_test.dart` skips.
class _FakeFetcher implements LinkPreviewFetcher {
  _FakeFetcher(this.response);

  LinkPreviewMetadata? response;
  int callCount = 0;

  int cancelCount = 0;
  int cancelAllCount = 0;

  @override
  Future<LinkPreviewMetadata?> fetch(String url) async {
    callCount++;
    return response;
  }

  @override
  void cancel(String url) => cancelCount++;

  @override
  void cancelAll() => cancelAllCount++;

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

/// Host-supplied fetcher that narrows the declared return type to the
/// non-nullable form — a legal covariant override. Reifies
/// `Future<LinkPreviewMetadata>`, so any `onTimeout: () => null` applied
/// directly to it throws a `TypeError` at the call boundary.
class _NarrowingFetcher implements LinkPreviewFetcher {
  _NarrowingFetcher(this.response);

  final LinkPreviewMetadata response;
  int callCount = 0;

  @override
  Future<LinkPreviewMetadata> fetch(String url) async {
    callCount++;
    return response;
  }

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
  const user = ChatUser(id: 'u1', displayName: 'Alice');

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(initialMessages: [], currentUser: user);
  });

  tearDown(() => controller.dispose());

  testWidgets('draft pre-fill populates the input when no editing is active', (
    tester,
  ) async {
    controller.setDraft('hello from draft');

    await tester.pumpWidget(
      wrap(
        MessageInput(controller: controller, onSendMessageRequest: (_) => true),
      ),
    );

    expect(find.text('hello from draft'), findsOneWidget);
  });

  testWidgets('typing a URL triggers the fetcher after the debounce', (
    tester,
  ) async {
    final fake = _FakeFetcher(
      const LinkPreviewMetadata(
        url: 'https://example.com',
        title: 'Example',
        description: 'It works',
      ),
    );

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) => true,
          linkPreviewFetcher: fake,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'visit https://example.com please',
    );
    // Wait for the debounce window (500ms) + fetch microtask.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(fake.callCount, 1);
  });

  testWidgets('clearing the URL cancels and resets preview state', (
    tester,
  ) async {
    final fake = _FakeFetcher(
      const LinkPreviewMetadata(url: 'https://example.com', title: 'Example'),
    );

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) => true,
          linkPreviewFetcher: fake,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'visit https://example.com');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    // Replace text with one that has no URL: state should reset.
    await tester.enterText(find.byType(TextField), 'plain text');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    // Now type a new URL — fetcher should fire again.
    await tester.enterText(find.byType(TextField), 'see https://other.com');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(fake.callCount, greaterThanOrEqualTo(2));
  });

  testWidgets('the fetched preview publishes chat_link_preview_close_button on '
      'both halves, and takes it away with the banner', (tester) async {
    final handle = WidgetsBinding.instance.ensureSemantics();
    final fake = _FakeFetcher(
      const LinkPreviewMetadata(url: 'https://example.com', title: 'Example'),
    );

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) => true,
          linkPreviewFetcher: fake,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('chat_link_preview_close_button')),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'visit https://example.com');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(
      find.semantics.byPredicate(
        (node) => node.identifier == 'chat_link_preview_close_button',
      ),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('chat_link_preview_close_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('chat_link_preview_close_button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat_link_preview_close_button')),
      findsNothing,
    );

    handle.dispose();
  });

  testWidgets('sending a message with a fetched preview includes metadata', (
    tester,
  ) async {
    final fake = _FakeFetcher(
      const LinkPreviewMetadata(
        url: 'https://example.com',
        title: 'Example',
        description: 'It works',
      ),
    );
    Map<String, dynamic>? receivedMetadata;

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (req) {
            receivedMetadata = req.metadata;
            return true;
          },
          linkPreviewFetcher: fake,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'check https://example.com');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    final sendButton = find.bySemanticsLabel('Send');
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(receivedMetadata, isNotNull);
    expect(receivedMetadata!['linkUrl'], 'https://example.com');
    expect(receivedMetadata!['linkTitle'], 'Example');
    expect(receivedMetadata!['linkDescription'], 'It works');
  });

  testWidgets(
    'send-before-debounce keeps the preview when the host fetcher narrows '
    'its return type to non-nullable',
    (tester) async {
      final narrowing = _NarrowingFetcher(
        const LinkPreviewMetadata(
          url: 'https://example.com',
          title: 'Example',
          description: 'It works',
        ),
      );
      Map<String, dynamic>? receivedMetadata;

      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (req) {
              receivedMetadata = req.metadata;
              return true;
            },
            linkPreviewFetcher: narrowing,
          ),
        ),
      );

      await tester.enterText(
        find.byType(TextField),
        'check https://example.com',
      );
      // Send inside the 500ms debounce window so the blocking send-time
      // fetch runs instead of reusing an already-rendered preview.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pumpAndSettle();

      expect(narrowing.callCount, greaterThanOrEqualTo(1));
      expect(receivedMetadata, isNotNull);
      expect(receivedMetadata!['linkUrl'], 'https://example.com');
      expect(receivedMetadata!['linkTitle'], 'Example');
    },
  );

  testWidgets('enableLinkPreview=false skips the fetcher entirely', (
    tester,
  ) async {
    final fake = _FakeFetcher(const LinkPreviewMetadata(url: 'https://x.com'));

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) => true,
          enableLinkPreview: false,
          linkPreviewFetcher: fake,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'https://x.com');
    await tester.pump(const Duration(milliseconds: 600));

    expect(fake.callCount, 0);
  });
}
