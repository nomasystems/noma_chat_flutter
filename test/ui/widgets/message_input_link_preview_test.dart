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

  @override
  Future<LinkPreviewMetadata?> fetch(String url) async {
    callCount++;
    return response;
  }

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
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
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
          onSendMessageRequest: (_) {},
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
          onSendMessageRequest: (_) {},
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
          onSendMessageRequest: (req) => receivedMetadata = req.metadata,
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

  testWidgets('enableLinkPreview=false skips the fetcher entirely', (
    tester,
  ) async {
    final fake = _FakeFetcher(const LinkPreviewMetadata(url: 'https://x.com'));

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          onSendMessageRequest: (_) {},
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
