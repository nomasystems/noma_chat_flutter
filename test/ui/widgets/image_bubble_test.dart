import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _FakeMediaLoader implements AttachmentMediaLoader {
  _FakeMediaLoader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) async => bytes;

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      throw UnimplementedError();

  @override
  void clear() {}
}

/// Encodes a solid-colour PNG of the requested pixel size, so a test can
/// assert on how the bubble reacts to a real aspect ratio.
Future<Uint8List> _pngOfSize(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ImageBubble', () {
    testWidgets('shows CachedNetworkImage with URL', (tester) async {
      await tester.pumpWidget(
        wrap(const ImageBubble(imageUrl: 'https://example.com/photo.jpg')),
      );
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://example.com/photo.jpg');
    });

    testWidgets('shows caption when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImageBubble(
            imageUrl: 'https://example.com/photo.jpg',
            caption: 'Nice view',
          ),
        ),
      );
      expect(find.text('Nice view'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://example.com/photo.jpg',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(CachedNetworkImage));
      expect(tapped, isTrue);
    });
  });

  group('ImageBubble — upload progress (R3a-6)', () {
    testWidgets(
      'shows a progress placeholder instead of CachedNetworkImage while '
      'uploadProgress is non-null, even with an empty imageUrl',
      (tester) async {
        final progress = ValueNotifier<double>(0.4);
        addTearDown(progress.dispose);
        await tester.pumpWidget(
          wrap(ImageBubble(imageUrl: '', uploadProgress: progress)),
        );

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('disables tap-to-open while uploading', (tester) async {
      final progress = ValueNotifier<double>(0.4);
      addTearDown(progress.dispose);
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: '',
            uploadProgress: progress,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('renders the real image and re-enables tap once uploadProgress '
        'clears', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: 'https://example.com/photo.jpg',
            uploadProgress: null,
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.tap(find.byType(CachedNetworkImage));
      expect(tapped, isTrue);
    });
  });

  group('ImageBubble — failed upload retry', () {
    testWidgets(
      'shows a retry icon instead of CachedNetworkImage when failed and '
      'onRetry is wired',
      (tester) async {
        await tester.pumpWidget(
          wrap(ImageBubble(imageUrl: '', isFailed: true, onRetry: () {})),
        );

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      },
    );

    testWidgets('tapping the retry icon calls onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: '',
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh));
      expect(retried, isTrue);
    });

    testWidgets('disables tap-to-open once failed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ImageBubble(
            imageUrl: '',
            isFailed: true,
            onRetry: () {},
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets(
      'still paints the failed placeholder when onRetry is not wired, with a '
      'static error glyph instead of a retry arrow that cannot work',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const ImageBubble(
              imageUrl: 'https://example.com/photo.jpg',
              isFailed: true,
            ),
          ),
        );

        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNothing);
      },
    );

    testWidgets(
      'never shows the retry icon while an upload is still in flight, even '
      'when isFailed and onRetry are both set',
      (tester) async {
        final progress = ValueNotifier<double>(0.4);
        addTearDown(progress.dispose);
        await tester.pumpWidget(
          wrap(
            ImageBubble(
              imageUrl: '',
              uploadProgress: progress,
              isFailed: true,
              onRetry: () {},
            ),
          ),
        );

        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });

  group('ImageBubble — bubble hugs the picture', () {
    const bubbleMaxWidth = 270.0;

    Future<Size> pumpAndMeasure(WidgetTester tester, Uint8List bytes) async {
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: bubbleMaxWidth),
              child: ImageBubble(
                imageUrl: 'https://example.com/photo.png',
                timestamp: DateTime(2024, 1, 1, 10, 30),
                mediaLoader: _FakeMediaLoader(bytes),
                attachmentRef: const AttachmentRef(
                  roomId: 'r1',
                  attachmentId: 'att-1',
                  fallbackUrl: 'https://example.com/photo.png',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Decoding an image is genuinely async — let the real clock run
      // briefly so the codec resolves before measuring.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
      return tester.getSize(find.byType(ImageBubble));
    }

    testWidgets('a portrait photo no longer stretches the bubble to the full '
        'available width', (tester) async {
      late final Uint8List bytes;
      await tester.runAsync(() async => bytes = await _pngOfSize(300, 600));

      final size = await pumpAndMeasure(tester, bytes);

      // 300x600 capped at the 250 max height ⇒ painted 125x250.
      expect(tester.getSize(find.byType(Image)), const Size(125, 250));
      expect(size.width, lessThan(bubbleMaxWidth));
      expect(size.width, 125);
    });

    testWidgets('a landscape photo still fills the available width', (
      tester,
    ) async {
      late final Uint8List bytes;
      await tester.runAsync(() async => bytes = await _pngOfSize(600, 300));

      final size = await pumpAndMeasure(tester, bytes);

      // 600x300 capped at 270 wide ⇒ painted 270x135, bubble unchanged.
      expect(size.width, bubbleMaxWidth);
    });

    testWidgets('the metadata row never squeezes below its own width', (
      tester,
    ) async {
      late final Uint8List bytes;
      await tester.runAsync(() async => bytes = await _pngOfSize(20, 400));

      final size = await pumpAndMeasure(tester, bytes);

      // A sliver scaled to the 250 max height is 12.5pt wide; the bubble
      // holds the metadata floor instead of clipping the timestamp.
      expect(size.width, 72);
      expect(tester.takeException(), isNull);
    });
  });
}
