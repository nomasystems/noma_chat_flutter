import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder findSemanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('FileBubble a11y', () {
    testWidgets('announces the file name as semantic label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FileBubble(
            fileName: 'contract.pdf',
            fileSize: '128 KB',
            mimeType: 'application/pdf',
            onTap: () {},
          ),
        ),
      );

      expect(findSemanticsWithLabel('contract.pdf'), findsOneWidget);
    });

    testWidgets('non-tappable bubble still surfaces the file name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const FileBubble(fileName: 'notes.txt', mimeType: 'text/plain')),
      );

      expect(findSemanticsWithLabel('notes.txt'), findsOneWidget);
    });
  });
}
