import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _PendingFetcher implements LinkPreviewFetcher {
  final _completer = Completer<LinkPreviewMetadata?>();
  int callCount = 0;

  @override
  Future<LinkPreviewMetadata?> fetch(String url) {
    callCount++;
    return _completer.future;
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

  testWidgets('two taps while the link preview is still pending send once', (
    tester,
  ) async {
    final fetcher = _PendingFetcher();
    final sent = <SendMessageRequest>[];

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          linkPreviewFetcher: fetcher,
          onSendMessageRequest: (request) {
            sent.add(request);
            return true;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'look at this https://example.com',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('chat_send_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('chat_send_button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(sent, isEmpty);

    await tester.pump(const Duration(seconds: 3));
    expect(sent.length, 1);
    expect(sent.single.text, 'look at this https://example.com');

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a further send is accepted once the first one is dispatched', (
    tester,
  ) async {
    final sent = <SendMessageRequest>[];

    await tester.pumpWidget(
      wrap(
        MessageInput(
          controller: controller,
          enableLinkPreview: false,
          onSendMessageRequest: (request) {
            sent.add(request);
            return true;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send_button')));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send_button')));
    await tester.pump();

    expect(sent.map((r) => r.text).toList(), ['first', 'second']);
  });
}
