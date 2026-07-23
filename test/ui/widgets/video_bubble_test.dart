import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('VideoBubble', () {
    testWidgets('shows play icon overlay', (tester) async {
      await tester.pumpWidget(
        wrap(const VideoBubble(videoUrl: 'https://example.com/video.mp4')),
      );
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows caption when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            caption: 'Check this out',
          ),
        ),
      );
      expect(find.text('Check this out'), findsOneWidget);
    });

    testWidgets('shows timestamp', (tester) async {
      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            timestamp: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );
      expect(find.text('09:05'), findsOneWidget);
    });
  });

  group('VideoBubble — upload progress (R3a-6)', () {
    testWidgets(
      'shows a progress placeholder instead of the play icon while '
      'uploadProgress is non-null',
      (tester) async {
        final progress = ValueNotifier<double>(0.2);
        addTearDown(progress.dispose);
        await tester.pumpWidget(
          wrap(VideoBubble(videoUrl: '', uploadProgress: progress)),
        );

        expect(find.byIcon(Icons.play_arrow), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('disables tap-to-open while uploading', (tester) async {
      final progress = ValueNotifier<double>(0.2);
      addTearDown(progress.dispose);
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: '',
            uploadProgress: progress,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('shows the play icon again once uploadProgress clears', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            uploadProgress: null,
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}
