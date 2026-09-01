import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/_authenticated_media_image.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, __, ___) => true;
  }
}

class _FakeMediaLoader implements AttachmentMediaLoader {
  _FakeMediaLoader({required this.onLoadBytes});

  final Future<Uint8List> Function(AttachmentRef ref) onLoadBytes;
  final List<AttachmentRef> requested = [];

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) {
    requested.add(ref);
    return onLoadBytes(ref);
  }

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      throw UnimplementedError();

  @override
  void clear() {}
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('MediaGalleryView', () {
    testWidgets('renders grid with correct number of items', (tester) async {
      final items = [
        const MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
        const MediaItem(
          url: 'https://example.com/2.jpg',
          type: MediaItemType.image,
        ),
        const MediaItem(
          url: 'https://example.com/3.mp4',
          type: MediaItemType.video,
        ),
      ];

      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();

      expect(find.byType(InkWell), findsNWidgets(3));
      // Only the 2 images fetch a source — the video item carries no
      // poster-frame URL, so it renders the static placeholder instead of
      // handing its clip's URL to CachedNetworkImage.
      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    });

    testWidgets('shows play icon for video items', (tester) async {
      final items = [
        const MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
        const MediaItem(
          url: 'https://example.com/2.mp4',
          type: MediaItemType.video,
        ),
      ];

      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();

      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    });

    testWidgets('calls onTapItem when tapped', (tester) async {
      MediaItem? tappedItem;
      final items = [
        const MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
      ];

      await tester.pumpWidget(
        wrap(
          MediaGalleryView(
            items: items,
            onTapItem: (item) => tappedItem = item,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(InkWell));
      expect(tappedItem, isNotNull);
      expect(tappedItem!.url, 'https://example.com/1.jpg');
    });

    testWidgets('shows empty state when no items', (tester) async {
      await tester.pumpWidget(wrap(const MediaGalleryView(items: [])));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No media'), findsOneWidget);
      expect(
        find.text(
          'Photos and videos you share in this conversation will '
          'appear here',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    });

    testWidgets('hides audio attachments by default', (tester) async {
      final items = [
        const MediaItem(
          url: 'https://example.com/song.mp3',
          type: MediaItemType.file,
          mimeType: 'audio/mpeg',
        ),
        const MediaItem(
          url: 'https://example.com/photo.jpg',
          type: MediaItemType.image,
          mimeType: 'image/jpeg',
        ),
      ];
      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('includes audio attachments when includeAudioFiles is true', (
      tester,
    ) async {
      final items = [
        const MediaItem(
          url: 'https://example.com/song.mp3',
          type: MediaItemType.file,
          mimeType: 'audio/mpeg',
          fileName: 'song.mp3',
        ),
      ];
      await tester.pumpWidget(
        wrap(MediaGalleryView(items: items, includeAudioFiles: true)),
      );
      await tester.pump();
      expect(find.text('song.mp3'), findsOneWidget);
    });

    testWidgets('shows empty state if all items are filtered out', (
      tester,
    ) async {
      final items = [
        const MediaItem(
          url: 'https://example.com/voice.m4a',
          type: MediaItemType.file,
          mimeType: 'audio/mp4',
        ),
      ];
      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    group('mediaLoader (B2 authenticated download)', () {
      // Minimal valid 1x1 transparent PNG so `Image.memory` decodes
      // without erroring.
      final validPngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      testWidgets('fetches bytes via mediaLoader when the item carries an '
          'attachmentRef, instead of handing CachedNetworkImage the URL', (
        tester,
      ) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async => validPngBytes,
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/photo.jpg',
            type: MediaItemType.image,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsNothing);
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<MemoryImage>());
        expect((image.image as MemoryImage).bytes, validPngBytes);
        expect(loader.requested.single.attachmentId, 'att-1');
      });

      testWidgets('renders via CachedNetworkImage unchanged when the item '
          'has no attachmentRef, even with a mediaLoader wired', (
        tester,
      ) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async => validPngBytes,
        );
        final items = [
          const MediaItem(
            url: 'https://example.com/photo.jpg',
            type: MediaItemType.image,
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsOneWidget);
        expect(loader.requested, isEmpty);
      });

      testWidgets('shows the broken-image fallback and retries once when '
          'the authenticated download fails', (tester) async {
        var calls = 0;
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async {
            calls++;
            throw StateError('401 unauthorized');
          },
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/photo.jpg',
            type: MediaItemType.image,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.byIcon(Icons.broken_image), findsOneWidget);
        expect(calls, 2);
      });

      testWidgets('fetches the poster frame via mediaLoader for a video '
          'tile, never the clip', (tester) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async => validPngBytes,
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/clip.mp4',
            type: MediaItemType.video,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'clip-1',
              fallbackUrl: 'https://signed.example/clip.mp4',
            ),
            thumbnailRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'poster-1',
              fallbackUrl: 'https://signed.example/poster.jpg',
            ),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(loader.requested.single.attachmentId, 'poster-1');
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<MemoryImage>());
        expect((image.image as MemoryImage).bytes, validPngBytes);
      });

      testWidgets('legacy video with no poster frame renders the '
          'placeholder and never calls mediaLoader or fetches the clip', (
        tester,
      ) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async {
            throw StateError('must not be called for a legacy video');
          },
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/clip.mp4',
            type: MediaItemType.video,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'clip-1',
              fallbackUrl: 'https://signed.example/clip.mp4',
            ),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();

        expect(loader.requested, isEmpty);
        expect(find.byType(AuthenticatedMediaImage), findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.broken_image), findsNothing);
        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      });

      testWidgets('a video with an empty thumbnailUrl and no '
          'thumbnailAttachmentId renders the placeholder and never calls '
          'mediaLoader', (tester) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async {
            throw StateError('must not be called for an empty thumbnailUrl');
          },
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/clip.mp4',
            type: MediaItemType.video,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'clip-1',
              fallbackUrl: 'https://signed.example/clip.mp4',
            ),
            thumbnailUrl: '',
            thumbnailRef: AttachmentRef(roomId: 'r1', fallbackUrl: ''),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();

        expect(loader.requested, isEmpty);
        expect(find.byType(AuthenticatedMediaImage), findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.broken_image), findsNothing);
        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      });

      testWidgets('a video whose thumbnailUrl carries no attachment id '
          'renders the placeholder and never calls mediaLoader or fetches '
          'that URL', (tester) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async {
            throw StateError('must not be called for an unresolvable poster');
          },
        );
        final items = [
          const MediaItem(
            url: 'https://signed.example/clip.mp4',
            type: MediaItemType.video,
            attachmentRef: AttachmentRef(
              roomId: 'r1',
              attachmentId: 'clip-1',
              fallbackUrl: 'https://signed.example/clip.mp4',
            ),
            thumbnailUrl: 'https://cdn.example.com/blobs/xyz.jpg',
            thumbnailRef: AttachmentRef(
              roomId: 'r1',
              fallbackUrl: 'https://cdn.example.com/blobs/xyz.jpg',
            ),
          ),
        ];

        await tester.pumpWidget(
          wrap(MediaGalleryView(items: items, mediaLoader: loader)),
        );
        await tester.pump();
        await tester.pump();

        expect(loader.requested, isEmpty);
        expect(find.byType(AuthenticatedMediaImage), findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.broken_image), findsNothing);
        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      });

      testWidgets('a video thumbnailUrl still renders via CachedNetworkImage '
          'when no mediaLoader is wired, even with no '
          'thumbnailAttachmentId', (tester) async {
        final items = [
          const MediaItem(
            url: 'https://example.com/clip.mp4',
            type: MediaItemType.video,
            thumbnailUrl: 'https://example.com/poster.jpg',
          ),
        ];

        await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsOneWidget);
      });
    });
  });
}
