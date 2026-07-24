import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

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

      expect(find.byType(CachedNetworkImage), findsNWidgets(3));
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
    });
  });
}
