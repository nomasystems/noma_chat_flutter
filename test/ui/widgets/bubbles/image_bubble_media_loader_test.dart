import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// B2 — the signed URL a bubble would otherwise load requires a Bearer
/// token no `CachedNetworkImage` sends, so it always 401s. With
/// `mediaLoader` wired the bubble fetches bytes through the authenticated
/// client instead and renders `Image.memory`.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // Minimal valid 1x1 transparent PNG so `Image.memory` decodes without
  // erroring (a real decode failure would trigger the retry path, which is
  // covered separately below).
  final validPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  group('ImageBubble + mediaLoader', () {
    testWidgets('fetches bytes via mediaLoader.loadBytes and renders '
        'Image.memory instead of CachedNetworkImage', (tester) async {
      final requested = <AttachmentRef>[];
      final loader = _FakeMediaLoader(
        onLoadBytes: (ref) async {
          requested.add(ref);
          return validPngBytes;
        },
      );

      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://signed.example/photo.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
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
      expect(requested.single.roomId, 'r1');
    });

    testWidgets('shows a spinner while bytes are loading, then the image', (
      tester,
    ) async {
      final completer = Completer<Uint8List>();
      final loader = _FakeMediaLoader(onLoadBytes: (_) => completer.future);

      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://signed.example/photo.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(validPngBytes);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('shows the broken-image fallback and retries once when the '
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
          ImageBubble(
            imageUrl: 'https://signed.example/photo.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      // One initial attempt + one retry — never an unbounded loop.
      expect(calls, 2);
    });

    testWidgets('ignores urlResolver when mediaLoader is wired (mediaLoader '
        'takes over rendering)', (tester) async {
      var urlResolverCalls = 0;
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://signed.example/photo.jpg',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
            urlResolver: (ref) async {
              urlResolverCalls++;
              return ref.fallbackUrl;
            },
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(urlResolverCalls, 0);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('renders via CachedNetworkImage unchanged when no '
        'mediaLoader is wired (no behaviour change)', (tester) async {
      await tester.pumpWidget(
        wrap(const ImageBubble(imageUrl: 'https://example.com/photo.jpg')),
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
