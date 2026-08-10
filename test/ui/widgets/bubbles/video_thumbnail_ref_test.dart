import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

class _RecordingMediaLoader implements AttachmentMediaLoader {
  _RecordingMediaLoader(this.bytes);

  final Uint8List bytes;
  final List<AttachmentRef> requested = [];

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) {
    requested.add(ref);
    return Future.value(bytes);
  }

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      throw UnimplementedError();

  @override
  void clear() {}
}

/// The poster frame is a **second blob** with its own attachment id, so
/// `MessageBubble` must hand `VideoBubble` the thumbnail's `AttachmentRef`
/// and never the clip's — feeding the clip's id to the authenticated
/// loader would download the video and ask `Image.memory` to decode it.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage videoMessage({String? thumbnailUrl, String? thumbnailId}) =>
      ChatMessage(
        id: 'm1',
        from: 'me',
        timestamp: DateTime(2026, 1, 1),
        messageType: MessageType.attachment,
        mimeType: 'video/mp4',
        attachmentUrl: 'https://cdn.example/media/att-video',
        attachmentId: 'att-video',
        thumbnailUrl: thumbnailUrl,
        thumbnailAttachmentId: thumbnailId,
      );

  VideoBubble bubbleOf(WidgetTester tester) =>
      tester.widget<VideoBubble>(find.byType(VideoBubble));

  testWidgets('passes the poster frame ref, not the video attachment ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: videoMessage(
            thumbnailUrl: 'https://cdn.example/media/att-thumb',
            thumbnailId: 'att-thumb',
          ),
          isOutgoing: true,
          roomId: 'r1',
        ),
      ),
    );

    final ref = bubbleOf(tester).thumbnailRef;
    expect(ref, isNotNull);
    expect(ref!.attachmentId, 'att-thumb');
    expect(ref.fallbackUrl, 'https://cdn.example/media/att-thumb');
    expect(ref.roomId, 'r1');
  });

  testWidgets('legacy videos keep the placeholder and carry no ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(message: videoMessage(), isOutgoing: true, roomId: 'r1'),
      ),
    );

    final bubble = bubbleOf(tester);
    expect(bubble.thumbnailRef, isNull);
    expect(bubble.thumbnailUrl, isNull);
    // Grey placeholder + videocam glyph, exactly as before poster frames
    // existed — no broken-image state, no crash.
    expect(find.byIcon(Icons.videocam), findsOneWidget);
  });

  testWidgets('a video with only a poster id still resolves a ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: videoMessage(thumbnailId: 'att-thumb'),
          isOutgoing: true,
          roomId: 'r1',
        ),
      ),
    );

    expect(bubbleOf(tester).thumbnailRef?.attachmentId, 'att-thumb');
  });

  group('a quoted video previews its poster frame, never the clip', () {
    // Minimal valid 1x1 transparent PNG so `Image.memory` decodes cleanly.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    final quoted = videoMessage(
      thumbnailUrl: 'https://cdn.example/media/att-thumb',
      thumbnailId: 'att-thumb',
    );

    testWidgets('inside the reply bubble', (tester) async {
      final loader = _RecordingMediaLoader(pngBytes);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage(
              id: 'm2',
              from: 'me',
              timestamp: DateTime(2026, 1, 1),
              text: 'look',
              messageType: MessageType.reply,
              referencedMessageId: 'm1',
            ),
            referencedMessage: quoted,
            isOutgoing: true,
            roomId: 'r1',
            attachmentMediaLoader: loader,
          ),
        ),
      );
      await tester.pump();

      expect(loader.requested.single.attachmentId, 'att-thumb');
    });

    testWidgets('inside the composer banner', (tester) async {
      final loader = _RecordingMediaLoader(pngBytes);
      final controller = ChatController(
        initialMessages: const [],
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      )..setRoomId('r1');
      addTearDown(controller.dispose);
      controller.setReplyTo(quoted);

      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, attachmentMediaLoader: loader),
        ),
      );
      await tester.pump();

      expect(loader.requested.single.attachmentId, 'att-thumb');
    });
  });
}
