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
}
