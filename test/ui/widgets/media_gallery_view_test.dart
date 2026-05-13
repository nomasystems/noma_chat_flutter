import 'dart:io';

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

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('MediaGalleryView', () {
    testWidgets('renders grid with correct number of items', (tester) async {
      final items = [
        MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
        MediaItem(
          url: 'https://example.com/2.jpg',
          type: MediaItemType.image,
        ),
        MediaItem(
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
        MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
        MediaItem(
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
        MediaItem(
          url: 'https://example.com/1.jpg',
          type: MediaItemType.image,
        ),
      ];

      await tester.pumpWidget(wrap(MediaGalleryView(
        items: items,
        onTapItem: (item) => tappedItem = item,
      )));
      await tester.pump();

      await tester.tap(find.byType(InkWell));
      expect(tappedItem, isNotNull);
      expect(tappedItem!.url, 'https://example.com/1.jpg');
    });

    testWidgets('shows empty state when no items', (tester) async {
      await tester.pumpWidget(wrap(
        const MediaGalleryView(items: []),
      ));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No media'), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    });

    testWidgets('hides audio attachments by default', (tester) async {
      final items = [
        MediaItem(
          url: 'https://example.com/song.mp3',
          type: MediaItemType.file,
          mimeType: 'audio/mpeg',
        ),
        MediaItem(
          url: 'https://example.com/photo.jpg',
          type: MediaItemType.image,
          mimeType: 'image/jpeg',
        ),
      ];
      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('includes audio attachments when includeAudioFiles is true',
        (tester) async {
      final items = [
        MediaItem(
          url: 'https://example.com/song.mp3',
          type: MediaItemType.file,
          mimeType: 'audio/mpeg',
          fileName: 'song.mp3',
        ),
      ];
      await tester.pumpWidget(wrap(MediaGalleryView(
        items: items,
        includeAudioFiles: true,
      )));
      await tester.pump();
      expect(find.text('song.mp3'), findsOneWidget);
    });

    testWidgets('shows empty state if all items are filtered out',
        (tester) async {
      final items = [
        MediaItem(
          url: 'https://example.com/voice.m4a',
          type: MediaItemType.file,
          mimeType: 'audio/mp4',
        ),
      ];
      await tester.pumpWidget(wrap(MediaGalleryView(items: items)));
      await tester.pump();
      expect(find.byType(EmptyState), findsOneWidget);
    });
  });
}
