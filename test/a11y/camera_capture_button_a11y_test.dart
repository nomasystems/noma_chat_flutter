import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'CameraCaptureButton exposes tap and long press actions to a screen reader',
    (tester) async {
      var shutter = false;
      var recordStarted = false;
      await tester.pumpWidget(
        wrap(
          CameraCaptureButton(
            ready: true,
            isRecording: false,
            onTap: () => shutter = true,
            onRecordStart: () => recordStarted = true,
            onRecordStop: () {},
          ),
        ),
      );
      await tester.pump();

      final finder = find.semantics.byLabel('Tap for photo, hold for video');
      tester.semantics.performAction(finder, SemanticsAction.tap);
      expect(shutter, isTrue);

      tester.semantics.performAction(finder, SemanticsAction.longPress);
      expect(recordStarted, isTrue);
    },
  );

  testWidgets('CameraCaptureButton stays inert while the camera is not ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const CameraCaptureButton(ready: false, isRecording: false)),
    );
    await tester.pump();

    final data = tester
        .getSemantics(find.byType(CameraCaptureButton))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.hasAction(SemanticsAction.longPress), isFalse);
  });
}
