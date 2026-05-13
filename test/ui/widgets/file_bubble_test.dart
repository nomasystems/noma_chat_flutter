import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('FileBubble', () {
    testWidgets('shows file name', (tester) async {
      await tester.pumpWidget(wrap(const FileBubble(fileName: 'report.pdf')));
      expect(find.text('report.pdf'), findsOneWidget);
    });

    testWidgets('shows file size when provided', (tester) async {
      await tester.pumpWidget(
        wrap(const FileBubble(fileName: 'report.pdf', fileSize: '2.4 MB')),
      );
      expect(find.text('2.4 MB'), findsOneWidget);
    });

    testWidgets('has Semantics label with file name', (tester) async {
      await tester.pumpWidget(wrap(const FileBubble(fileName: 'report.pdf')));
      final finder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'report.pdf',
      );
      expect(finder, findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(FileBubble(fileName: 'report.pdf', onTap: () => tapped = true)),
      );
      await tester.tap(find.text('report.pdf'));
      expect(tapped, isTrue);
    });
  });
}
