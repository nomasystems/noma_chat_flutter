import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late int sends;
  late int retakes;
  late int discards;

  setUp(() {
    sends = 0;
    retakes = 0;
    discards = 0;
  });

  Future<void> pumpReview(
    WidgetTester tester, {
    required bool isVideo,
    ChatTheme theme = ChatTheme.defaults,
    CameraVideoPreviewBuilder? videoPreviewBuilder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraCaptureReview(
            result: CameraCaptureResult(
              file: XFile(isVideo ? '/tmp/clip.mp4' : '/tmp/shot.jpg'),
              isVideo: isVideo,
            ),
            theme: theme,
            videoPreviewBuilder: videoPreviewBuilder,
            onSend: () => sends++,
            onRetake: () => retakes++,
            onDiscard: () => discards++,
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('each control reports only its own decision', (tester) async {
    await pumpReview(tester, isVideo: false);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect([sends, retakes, discards], [1, 0, 0]);

    await tester.tap(find.text('Retake'));
    await tester.pump();
    expect([sends, retakes, discards], [1, 1, 0]);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect([sends, retakes, discards], [1, 1, 1]);
  });

  testWidgets(
    'all three exits carry a screen-reader label, since two of them are '
    'bare icons',
    (tester) async {
      await pumpReview(tester, isVideo: false);

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      expect(find.bySemanticsLabel('Discard'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    },
  );

  testWidgets(
    'a still is shown as a picture, and a photo that will not decode still '
    'leaves the three exits reachable',
    (tester) async {
      await pumpReview(tester, isVideo: false);

      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'an undecodable file must not take the review down with it',
      );
      expect(find.byIcon(Icons.send), findsOneWidget);
    },
  );

  testWidgets('a clip goes through the preview builder, still, not through '
      'the photo path', (tester) async {
    XFile? seen;

    await pumpReview(
      tester,
      isVideo: true,
      videoPreviewBuilder: (context, file, theme) {
        seen = file;
        return const Text('stub preview');
      },
    );

    expect(seen?.path, '/tmp/clip.mp4');
    expect(find.text('stub preview'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the Retake label follows the theme\'s own action style', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 22, color: Color(0xFF00FF00));

    await pumpReview(
      tester,
      isVideo: false,
      theme: const ChatTheme(cameraCaptureReviewActionStyle: style),
    );

    expect(tester.widget<Text>(find.text('Retake')).style, style);
  });
}
