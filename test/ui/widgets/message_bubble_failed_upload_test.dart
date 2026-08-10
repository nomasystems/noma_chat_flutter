import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// `retrySend` refuses a media row whose bytes never reached the server, so
/// the bubble must not paint the media-level retry arrow there: the arrow
/// would be a button that cannot work, and painting it also suppressed the
/// metadata-row icon that used to explain the failure.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// The provisional row `ChatMessagesController.sendAttachment` adds before
  /// the upload starts: empty URL, no id, metadata with no blob reference.
  ChatMessage neverUploaded() => ChatMessage(
    id: 'tmp-1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    messageType: MessageType.attachment,
    mimeType: 'image/jpeg',
    attachmentUrl: '',
    fileName: 'photo.jpg',
    fileSize: '1024',
    metadata: const {
      'mimeType': 'image/jpeg',
      'fileName': 'photo.jpg',
      'fileSize': '1024',
    },
  );

  /// Upload landed, the send itself failed — retrying re-posts the same
  /// blob under the same id.
  ChatMessage uploadedButUnsent() => ChatMessage(
    id: 'tmp-2',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    messageType: MessageType.attachment,
    mimeType: 'image/jpeg',
    attachmentUrl: 'https://cdn.example/media/att-1',
    attachmentId: 'att-1',
  );

  group('MessageBubble — failed upload that no retry can clear', () {
    testWidgets('paints no retry arrow and keeps the status-row error icon', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: neverUploaded(),
            isOutgoing: true,
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsNothing);
      // Media badge + metadata row.
      expect(find.byIcon(Icons.error_outline), findsNWidgets(2));

      // The metadata-row icon still routes to onRetry — under NomaChatView
      // that surfaces the localized "pick the file again" notice.
      await tester.tap(find.byIcon(Icons.error_outline).last);
      expect(retried, isTrue);
    });

    testWidgets('a metadata-only blob reference still counts as uploaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: neverUploaded().copyWith(
              metadata: const {'attachmentId': 'att-9'},
            ),
            isOutgoing: true,
            isFailed: true,
            onRetry: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('an uploaded-but-unsent row keeps the working retry arrow', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: uploadedButUnsent(),
            isOutgoing: true,
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await tester.tap(find.byIcon(Icons.refresh));
      expect(retried, isTrue);
    });

    testWidgets('a failed text message keeps the status-row retry it always '
        'had', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage(
              id: 'm1',
              from: 'u1',
              timestamp: DateTime(2026, 1, 1),
              text: 'oops',
            ),
            isOutgoing: true,
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.error_outline));
      expect(retried, isTrue);
    });

    testWidgets('an in-flight upload never shows a failed state alongside the '
        'ring', (tester) async {
      final progress = ValueNotifier<double>(0.3);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: uploadedButUnsent(),
            isOutgoing: true,
            isFailed: true,
            onRetry: () {},
            attachmentUploadProgress: progress,
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The metadata-row icon is not suppressed while uploading either.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('MessageBubble — cancel-upload accessibility action', () {
    ChatMessage voiceNote() => ChatMessage(
      id: 'v1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      messageType: MessageType.audio,
      mimeType: 'audio/mp4',
      attachmentUrl: '',
    );

    /// Custom-action labels the bubble exposes to a screen reader. Anchored
    /// on the media bubble because `MessageBubble`'s own semantics node sits
    /// above it, and its `excludeSemantics` drops everything below.
    Future<Set<String>> customActionLabels(
      WidgetTester tester,
      ChatMessage message,
      Finder anchor,
    ) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      final progress = ValueNotifier<double>(0.4);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            isOutgoing: true,
            attachmentUploadProgress: progress,
            audioUploadProgress: progress,
            onCancelAttachmentUpload: () {},
          ),
        ),
      );

      final ids =
          tester
              .getSemantics(anchor)
              .getSemanticsData()
              .customSemanticsActionIds ??
          const <int>[];
      return {
        for (final id in ids)
          if (CustomSemanticsAction.getAction(id)?.label case final label?)
            label,
      };
    }

    testWidgets('is not announced on an uploading voice note — sendVoice '
        'registers no cancel token and AudioBubble paints no X', (
      tester,
    ) async {
      expect(
        await customActionLabels(tester, voiceNote(), find.byType(AudioBubble)),
        isEmpty,
      );
    });

    testWidgets('is announced on an uploading photo, which does paint one', (
      tester,
    ) async {
      expect(
        await customActionLabels(
          tester,
          neverUploaded(),
          find.byType(ImageBubble),
        ),
        contains('Cancel upload'),
      );
    });
  });
}
