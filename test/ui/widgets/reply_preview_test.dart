import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

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

  ChatMessage makeMessage({
    String? text = 'Hello',
    MessageType messageType = MessageType.regular,
    String? mimeType,
    String? fileName,
    String? attachmentUrl,
  }) {
    return ChatMessage(
      id: 'msg1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: text,
      messageType: messageType,
      mimeType: mimeType,
      fileName: fileName,
      attachmentUrl: attachmentUrl,
    );
  }

  group('ReplyPreview', () {
    testWidgets('shows message text', (tester) async {
      await tester.pumpWidget(
        wrap(ReplyPreview(message: makeMessage(text: 'Reply text'))),
      );

      expect(find.text('Reply text'), findsOneWidget);
    });

    testWidgets('shows sender name when provided', (tester) async {
      await tester.pumpWidget(
        wrap(ReplyPreview(message: makeMessage(), senderName: 'Bob')),
      );

      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows dismiss button when onDismiss provided', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(),
            onDismiss: () => dismissed = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('dismiss button has 48x48 touch target', (tester) async {
      await tester.pumpWidget(
        wrap(ReplyPreview(message: makeMessage(), onDismiss: () {})),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 48 && widget.height == 48,
        ),
      );
      expect(sizedBox.width, 48);
      expect(sizedBox.height, 48);
    });

    testWidgets('shows image icon and label for image attachment', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'image/jpeg',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
    });

    testWidgets('shows image icon with caption for image with text', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: 'Look at this',
              messageType: MessageType.attachment,
              mimeType: 'image/png',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.text('Look at this'), findsOneWidget);
    });

    testWidgets('shows video icon and label for video attachment', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'video/mp4',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('shows mic icon and label for audio message', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(text: null, messageType: MessageType.audio),
          ),
        ),
      );

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows mic icon for audio attachment', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'audio/mp3',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows file icon and filename for file attachment', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'application/pdf',
              fileName: 'report.pdf',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
    });

    testWidgets('shows no icon for regular text message', (tester) async {
      await tester.pumpWidget(
        wrap(ReplyPreview(message: makeMessage(text: 'Hello'))),
      );

      expect(find.byIcon(Icons.image), findsNothing);
      expect(find.byIcon(Icons.videocam), findsNothing);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(text: 'Tap me'),
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      expect(tapped, isTrue);
    });

    testWidgets('shows thumbnail for image attachment', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'image/jpeg',
              attachmentUrl: 'https://example.com/photo.jpg',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('does not show thumbnail for non-image attachment', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: makeMessage(
              text: null,
              messageType: MessageType.attachment,
              mimeType: 'application/pdf',
              fileName: 'doc.pdf',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
    });

    group('mediaLoader (B2 authenticated download)', () {
      // Minimal valid 1x1 transparent PNG so `Image.memory` decodes
      // without erroring.
      final validPngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      const attachmentRef = AttachmentRef(
        roomId: 'r1',
        attachmentId: 'att-1',
        fallbackUrl: 'https://signed.example/photo.jpg',
      );

      testWidgets('fetches the thumbnail bytes via mediaLoader instead of '
          'handing Image.network the signed URL', (tester) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async => validPngBytes,
        );

        await tester.pumpWidget(
          wrap(
            ReplyPreview(
              message: makeMessage(
                text: null,
                messageType: MessageType.attachment,
                mimeType: 'image/jpeg',
                attachmentUrl: 'https://signed.example/photo.jpg',
              ),
              mediaLoader: loader,
              attachmentRef: attachmentRef,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<MemoryImage>());
        expect((image.image as MemoryImage).bytes, validPngBytes);
        expect(loader.requested.single.attachmentId, 'att-1');
        expect(loader.requested.single.roomId, 'r1');
      });

      testWidgets('shows the plain Image.network thumbnail unchanged when '
          'mediaLoader is wired but attachmentRef is not (no behaviour '
          'change)', (tester) async {
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async => validPngBytes,
        );

        await tester.pumpWidget(
          wrap(
            ReplyPreview(
              message: makeMessage(
                text: null,
                messageType: MessageType.attachment,
                mimeType: 'image/jpeg',
                attachmentUrl: 'https://example.com/photo.jpg',
              ),
              mediaLoader: loader,
            ),
          ),
        );
        await tester.pump();

        expect(loader.requested, isEmpty);
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isNot(isA<MemoryImage>()));
      });

      testWidgets('shows nothing (no crash) when the authenticated '
          'download fails, without retrying more than once', (tester) async {
        var calls = 0;
        final loader = _FakeMediaLoader(
          onLoadBytes: (_) async {
            calls++;
            throw StateError('401 unauthorized');
          },
        );

        await tester.pumpWidget(
          wrap(
            ReplyPreview(
              message: makeMessage(
                text: null,
                messageType: MessageType.attachment,
                mimeType: 'image/jpeg',
                attachmentUrl: 'https://signed.example/photo.jpg',
              ),
              mediaLoader: loader,
              attachmentRef: attachmentRef,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(calls, 2);
      });
    });
  });
}
