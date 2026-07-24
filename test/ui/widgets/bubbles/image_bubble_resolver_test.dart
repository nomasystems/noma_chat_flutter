import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ImageBubble + urlResolver', () {
    testWidgets(
      'renders the plain imageUrl unchanged when no resolver is wired '
      '(no behaviour change)',
      (tester) async {
        await tester.pumpWidget(
          wrap(const ImageBubble(imageUrl: 'https://example.com/photo.jpg')),
        );
        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.imageUrl, 'https://example.com/photo.jpg');
        expect(image.cacheKey, isNull);
      },
    );

    testWidgets('swaps to the resolver-provided URL once it resolves', (
      tester,
    ) async {
      final requested = <AttachmentRef>[];
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://stale.example/photo.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://stale.example/photo.jpg',
            ),
            urlResolver: (ref) async {
              requested.add(ref);
              return 'https://signed.example/fresh.jpg';
            },
          ),
        ),
      );

      // First frame paints the fallback synchronously — no flash of
      // nothing while the resolver's Future is in flight.
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        'https://stale.example/photo.jpg',
      );

      await tester.pump();
      await tester.pump();

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://signed.example/fresh.jpg');
      expect(image.cacheKey, 'att-1');
      expect(requested.single.attachmentId, 'att-1');
      expect(requested.single.roomId, 'r1');
    });

    testWidgets('does not call the resolver when attachmentRef is null even if '
        'urlResolver is set', (tester) async {
      var resolverCalls = 0;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://example.com/photo.jpg',
            urlResolver: (ref) async {
              resolverCalls++;
              return ref.fallbackUrl;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(resolverCalls, 0);
    });

    testWidgets('re-resolves when attachmentId changes on rebuild', (
      tester,
    ) async {
      final requestedIds = <String?>[];
      Future<String> resolver(AttachmentRef ref) async {
        requestedIds.add(ref.attachmentId);
        return 'https://signed.example/${ref.attachmentId}';
      }

      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://x/1.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://x/1.jpg',
            ),
            urlResolver: resolver,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://x/2.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-2',
              fallbackUrl: 'https://x/2.jpg',
            ),
            urlResolver: resolver,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(requestedIds, ['att-1', 'att-2']);
    });
  });
}
