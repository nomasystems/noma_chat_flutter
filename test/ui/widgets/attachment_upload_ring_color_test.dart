import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/bubbles/_attachment_upload_overlay.dart';

/// The ring marks the same thing the read tick does — the message made it —
/// so it takes the read tick's colour before the muted pending-tick one.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Color ringColor(WidgetTester tester) {
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    return (indicator.valueColor! as AlwaysStoppedAnimation<Color>).value;
  }

  Future<void> pumpRing(WidgetTester tester, ChatBubbleTheme bubble) async {
    await tester.pumpWidget(
      wrap(
        AttachmentUploadRing(
          progress: ValueNotifier<double>(0.5),
          theme: ChatTheme(bubble: bubble),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an explicit uploadProgressColor wins over everything', (
    tester,
  ) async {
    await pumpRing(
      tester,
      const ChatBubbleTheme(
        uploadProgressColor: Color(0xFF112233),
        statusReadColor: Color(0xFF00FF00),
        statusColor: Color(0xFF888888),
      ),
    );

    expect(ringColor(tester), const Color(0xFF112233));
  });

  testWidgets('falls back to the read-tick colour, not the pending one', (
    tester,
  ) async {
    await pumpRing(
      tester,
      const ChatBubbleTheme(
        statusReadColor: Color(0xFF00FF00),
        statusColor: Color(0xFF888888),
      ),
    );

    expect(ringColor(tester), const Color(0xFF00FF00));
  });

  testWidgets('falls back to statusColor when the host themes no read tick', (
    tester,
  ) async {
    await pumpRing(
      tester,
      const ChatBubbleTheme(statusColor: Color(0xFF888888)),
    );

    expect(ringColor(tester), const Color(0xFF888888));
  });

  testWidgets('falls back to the palette default with a bare theme', (
    tester,
  ) async {
    await pumpRing(tester, const ChatBubbleTheme());

    expect(ringColor(tester), DefaultPalette.uploadProgressColor);
  });
}
