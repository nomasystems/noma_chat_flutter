import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const theme = ChatTheme.defaults;
  final l10n = theme.l10n;

  Future<Future<String?>> openDialog(
    WidgetTester tester, {
    String? title,
    String? reasonHint,
  }) async {
    late Future<String?> pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                pending = ReportMessageDialog.show(
                  context,
                  theme: theme,
                  title: title,
                  reasonHint: reasonHint,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return pending;
  }

  group('ReportMessageDialog', () {
    testWidgets('renders the title, field and actions', (tester) async {
      await openDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.reportMessageTitle), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(l10n.cancel), findsOneWidget);
      expect(find.text(l10n.report), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
    });

    testWidgets('uses the custom title and reason hint when supplied', (
      tester,
    ) async {
      await openDialog(tester, title: 'Flag it', reasonHint: 'Why?');

      expect(find.text('Flag it'), findsOneWidget);
      expect(find.text(l10n.reportMessageTitle), findsNothing);
      expect(find.text('Why?'), findsOneWidget);
    });

    testWidgets('report stays disabled until a non-empty reason is typed', (
      tester,
    ) async {
      await openDialog(tester);

      TextButton reportButton() => tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.report),
      );

      expect(reportButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(reportButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'spam');
      await tester.pump();
      expect(reportButton().onPressed, isNotNull);
    });

    testWidgets('submit resolves to the trimmed reason', (tester) async {
      final result = await openDialog(tester);

      await tester.enterText(find.byType(TextField), '  abusive  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, l10n.report));
      await tester.pumpAndSettle();

      expect(await result, 'abusive');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancel resolves to null', (tester) async {
      final result = await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'something');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
