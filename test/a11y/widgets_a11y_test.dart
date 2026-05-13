import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Lightweight accessibility audit for the most prominent UI Kit widgets.
/// Uses Flutter's built-in `AccessibilityGuideline` matchers — these check
/// tap target sizes, label presence and Material text-contrast against the
/// rendered theme. Failing any of them is a real regression worth fixing.
void main() {
  Future<void> auditAll(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('MessageBubble (outgoing text) meets a11y guidelines', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: ChatMessage(
            id: 'm1',
            from: 'u1',
            timestamp: DateTime(2026, 5, 12, 10),
            text: 'Hello accessibility',
          ),
          isOutgoing: true,
        ),
      ),
    );
    await auditAll(tester);
  });

  testWidgets('AttachmentPickerSheet meets a11y guidelines', (tester) async {
    await tester.pumpWidget(
      wrap(
        AttachmentPickerSheet(
          onPickCamera: () {},
          onPickGallery: () {},
          onPickFile: () {},
        ),
      ),
    );
    await auditAll(tester);
  });

  testWidgets('VoiceRecorderButton meets a11y guidelines', (tester) async {
    await tester.pumpWidget(wrap(const VoiceRecorderButton()));
    await auditAll(tester);
  });

  testWidgets('RoomListView (empty) meets a11y guidelines', (tester) async {
    await tester.pumpWidget(
      wrap(
        RoomListView(
          controller: RoomListController(),
          showHeader: false,
          showSearch: false,
        ),
      ),
    );
    await auditAll(tester);
  });

  testWidgets('RoomListView with rooms meets a11y guidelines', (tester) async {
    final controller = RoomListController()
      ..addRoom(const RoomListItem(id: 'r1', name: 'Alpha'))
      ..addRoom(const RoomListItem(id: 'r2', name: 'Beta'));

    await tester.pumpWidget(
      wrap(
        RoomListView(
          controller: controller,
          showHeader: false,
          showSearch: false,
        ),
      ),
    );
    await auditAll(tester);
  });
}
