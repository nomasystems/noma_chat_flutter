import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

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
}
