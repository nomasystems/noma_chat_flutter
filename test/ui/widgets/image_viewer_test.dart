import 'dart:async';
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
  Widget wrap(Widget child) => MaterialApp(home: child);

  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  // Minimal valid 1x1 transparent PNG so `Image.memory` decodes without
  // erroring.
  final validPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  group('ImageViewer', () {
    testWidgets('renders via CachedNetworkImage unchanged when no '
        'mediaLoader is wired (no behaviour change)', (tester) async {
      await tester.pumpWidget(
        wrap(const ImageViewer(imageUrl: 'https://example.com/photo.jpg')),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://example.com/photo.jpg');
    });

    testWidgets('renders via CachedNetworkImage unchanged when mediaLoader '
        'is wired but attachmentRef is not (no behaviour change)', (
      tester,
    ) async {
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        wrap(
          ImageViewer(
            imageUrl: 'https://example.com/photo.jpg',
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(loader.requested, isEmpty);
    });

    testWidgets('fetches bytes via mediaLoader.loadBytes and renders '
        'Image.memory instead of CachedNetworkImage', (tester) async {
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        wrap(
          ImageViewer(
            imageUrl: 'https://signed.example/photo.jpg',
            mediaLoader: loader,
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, validPngBytes);
      expect(loader.requested.single.attachmentId, 'att-1');
      expect(loader.requested.single.roomId, 'r1');
    });

    testWidgets('shows a spinner while bytes are loading, then the image', (
      tester,
    ) async {
      final completer = Completer<Uint8List>();
      final loader = _FakeMediaLoader(onLoadBytes: (_) => completer.future);

      await tester.pumpWidget(
        wrap(
          ImageViewer(
            imageUrl: 'https://signed.example/photo.jpg',
            mediaLoader: loader,
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
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
          ImageViewer(
            imageUrl: 'https://signed.example/photo.jpg',
            mediaLoader: loader,
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/photo.jpg',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('has a close button that pops the route', (tester) async {
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImageViewer(
                    imageUrl: 'https://signed.example/photo.jpg',
                    mediaLoader: loader,
                    attachmentRef: const AttachmentRef(
                      roomId: 'r1',
                      attachmentId: 'att-1',
                      fallbackUrl: 'https://signed.example/photo.jpg',
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsNothing);
    });
  });
}
