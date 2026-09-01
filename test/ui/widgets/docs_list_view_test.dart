import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('DocsListView empty state', () {
    testWidgets('says what will fill the tab, not just that it is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DocsListView(items: [])),
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No documents shared yet'), findsOneWidget);
      expect(
        find.text('Documents you share in this conversation will appear here'),
        findsOneWidget,
      );
    });
  });
}
