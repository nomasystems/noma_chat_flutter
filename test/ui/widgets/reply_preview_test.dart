import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

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
  });
}
