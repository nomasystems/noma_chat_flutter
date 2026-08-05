import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// Outermost [Semantics] the bubble itself builds — the node that tells
  /// assistive tech whether the video is pressable.
  Semantics semanticsOf(WidgetTester tester) => tester.widget<Semantics>(
    find
        .descendant(
          of: find.byType(VideoBubble),
          matching: find.byType(Semantics),
        )
        .first,
  );

  group('VideoBubble', () {
    testWidgets('shows play icon overlay when a tap handler is wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          VideoBubble(videoUrl: 'https://example.com/video.mp4', onTap: () {}),
        ),
      );
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('paints no play affordance without a tap handler', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const VideoBubble(videoUrl: 'https://example.com/video.mp4')),
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(semanticsOf(tester).properties.button, isFalse);
    });

    testWidgets('the wired overlay opens the video', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        wrap(
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            onTap: () => opened = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(opened, isTrue);
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
    testWidgets('shows a progress placeholder instead of the play icon while '
        'uploadProgress is non-null', (tester) async {
      final progress = ValueNotifier<double>(0.2);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        wrap(VideoBubble(videoUrl: '', uploadProgress: progress, onTap: () {})),
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(semanticsOf(tester).properties.button, isFalse);
    });

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
          VideoBubble(
            videoUrl: 'https://example.com/video.mp4',
            uploadProgress: null,
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}
