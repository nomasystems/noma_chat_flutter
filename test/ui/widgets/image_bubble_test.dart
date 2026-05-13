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
}
