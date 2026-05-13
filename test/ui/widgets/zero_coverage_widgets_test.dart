import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Coverage for widgets that previously had no test at all
/// (`DocsListView`, `ImageViewer`, `FullEmojiPicker`, `LinkPreviewBubble`).
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('DocsListView', () {
    testWidgets('shows empty state when no docs', (tester) async {
      await tester.pumpWidget(wrap(const DocsListView(items: [])));
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('renders a list of files with their names', (tester) async {
      final items = [
        MediaItem(
          url: 'https://x/y.pdf',
          type: MediaItemType.file,
          fileName: 'notes.pdf',
          mimeType: 'application/pdf',
          timestamp: DateTime(2026, 1, 1),
        ),
        MediaItem(
          url: 'https://x/data.csv',
          type: MediaItemType.file,
          fileName: 'data.csv',
          mimeType: 'text/csv',
        ),
        MediaItem(
          url: 'https://x/zip.zip',
          type: MediaItemType.file,
          fileName: 'archive.zip',
          mimeType: 'application/zip',
        ),
      ];

      await tester.pumpWidget(wrap(DocsListView(items: items)));

      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('data.csv'), findsOneWidget);
      expect(find.text('archive.zip'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('hides audio files by default; shows them when toggled', (
      tester,
    ) async {
      final items = [
        MediaItem(
          url: 'https://x/a.mp3',
          type: MediaItemType.file,
          fileName: 'song.mp3',
          mimeType: 'audio/mpeg',
        ),
      ];

      // Default: audio hidden → empty state.
      await tester.pumpWidget(wrap(DocsListView(items: items)));
      expect(find.byType(EmptyState), findsOneWidget);

      // includeAudioFiles=true: audio visible.
      await tester.pumpWidget(
        wrap(DocsListView(items: items, includeAudioFiles: true)),
      );
      expect(find.text('song.mp3'), findsOneWidget);
    });

    testWidgets('tap fires onTapItem with the tapped doc', (tester) async {
      MediaItem? tapped;
      final items = [
        MediaItem(
          url: 'https://x/y.pdf',
          type: MediaItemType.file,
          fileName: 'doc.pdf',
        ),
      ];

      await tester.pumpWidget(
        wrap(DocsListView(items: items, onTapItem: (m) => tapped = m)),
      );
      await tester.tap(find.text('doc.pdf'));
      await tester.pump();

      expect(tapped?.fileName, 'doc.pdf');
    });

    testWidgets('non-file MediaItems are filtered out', (tester) async {
      final items = [
        MediaItem(url: 'https://x/img.jpg', type: MediaItemType.image),
        MediaItem(url: 'https://x/vid.mp4', type: MediaItemType.video),
      ];

      await tester.pumpWidget(wrap(DocsListView(items: items)));
      expect(find.byType(EmptyState), findsOneWidget);
    });
  });

  group('ImageViewer', () {
    testWidgets('renders without hero tag', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageViewer(imageUrl: 'https://example.com/x.jpg'),
        ),
      );
      await tester.pump(); // single pump to settle the appbar

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('renders with hero tag wrapping the image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageViewer(
            imageUrl: 'https://example.com/x.jpg',
            heroTag: 'hero-1',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Hero), findsOneWidget);
    });

    testWidgets('close button pops the route', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const ImageViewer(imageUrl: 'https://example.com/x.jpg'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ImageViewer), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewer), findsNothing);
    });
  });

  group('LinkPreviewBubble', () {
    testWidgets('renders the title + description + domain', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LinkPreviewBubble(
            url: 'https://flutter.dev/showcase',
            title: 'Showcase apps',
            description: 'Built with Flutter.',
          ),
        ),
      );

      expect(find.text('Showcase apps'), findsOneWidget);
      expect(find.text('Built with Flutter.'), findsOneWidget);
      expect(find.textContaining('flutter.dev'), findsOneWidget);
    });

    testWidgets('renders without image (no exception)', (tester) async {
      await tester.pumpWidget(
        wrap(const LinkPreviewBubble(url: 'https://example.com/path')),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // FullEmojiPicker only exposes a static `show` that pops a modal sheet;
  // we exercise it just enough to compile the bottom-sheet builder.
  group('FullEmojiPicker', () {
    testWidgets('show opens a modal bottom sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  // Fire-and-forget; the modal closes when the test tears down.
                  FullEmojiPicker.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // A single pump is enough to schedule the modal; we don't drive it
      // further because the emoji picker package itself loads platform
      // resources that we don't want to invoke in unit tests.
      await tester.pump();
    });
  });
}
