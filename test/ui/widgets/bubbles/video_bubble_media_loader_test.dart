import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// B2 — the thumbnail's signed URL requires a Bearer token no
/// `CachedNetworkImage` sends, so it always 401s. With `mediaLoader` wired
/// the bubble fetches the thumbnail's bytes through the authenticated
/// client instead. Playback itself stays the host's responsibility — the
/// SDK's `VideoBubble` only ever renders a thumbnail.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final validPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  group('VideoBubble + mediaLoader', () {
    testWidgets('fetches the thumbnail bytes via mediaLoader.loadBytes and '
        'renders Image.memory instead of CachedNetworkImage', (tester) async {
      final requested = <AttachmentRef>[];
      final loader = _FakeMediaLoader(
        onLoadBytes: (ref) async {
          requested.add(ref);
          return validPngBytes;
        },
      );

      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            thumbnailUrl: 'https://signed.example/thumb.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/thumb.jpg',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, validPngBytes);
      expect(requested.single.attachmentId, 'att-1');
    });

    testWidgets('shows the placeholder fallback and retries once when the '
        'authenticated download fails', (tester) async {
      var calls = 0;
      final loader = _FakeMediaLoader(
        onLoadBytes: (_) async {
          calls++;
          throw StateError('401 unauthorized');
        },
      );

      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            thumbnailUrl: 'https://signed.example/thumb.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/thumb.jpg',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.videocam), findsWidgets);
      expect(calls, 2);
    });

    testWidgets('does not use mediaLoader when there is no thumbnailUrl at '
        'all (falls to the placeholder, no crash)', (tester) async {
      var calls = 0;
      final loader = _FakeMediaLoader(
        onLoadBytes: (_) async {
          calls++;
          return validPngBytes;
        },
      );

      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://example.com/video.mp4',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(calls, 0);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders via CachedNetworkImage unchanged when no '
        'mediaLoader is wired (no behaviour change)', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            thumbnailUrl: 'https://example.com/thumb.jpg',
          ),
        ),
      );
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });
}

class _FakeMediaLoader implements AttachmentMediaLoader {
  _FakeMediaLoader({required this.onLoadBytes});

  final Future<Uint8List> Function(AttachmentRef ref) onLoadBytes;

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) => onLoadBytes(ref);

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      throw UnimplementedError();

  @override
  void clear() {}
}
