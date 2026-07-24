import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('VideoBubble + urlResolver', () {
    testWidgets(
      'renders the plain thumbnailUrl unchanged when no resolver is wired',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const VideoBubble(
              videoUrl: 'https://example.com/video.mp4',
              thumbnailUrl: 'https://example.com/thumb.jpg',
            ),
          ),
        );
        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.imageUrl, 'https://example.com/thumb.jpg');
      },
    );

    testWidgets('swaps to the resolver-provided thumbnail URL once it '
        'resolves', (tester) async {
      final requested = <AttachmentRef>[];
      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            thumbnailUrl: 'https://stale.example/thumb.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://stale.example/thumb.jpg',
            ),
            urlResolver: (ref) async {
              requested.add(ref);
              return 'https://signed.example/fresh-thumb.jpg';
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://signed.example/fresh-thumb.jpg');
      expect(requested.single.attachmentId, 'att-1');
    });

    testWidgets('does not resolve when there is no thumbnailUrl at all', (
      tester,
    ) async {
      var resolverCalls = 0;
      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://example.com/video.mp4',
            ),
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
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}
