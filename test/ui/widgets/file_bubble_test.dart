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

  group('FileBubble — upload progress (R3a-6)', () {
    testWidgets('shows a progress ring instead of the file-type icon while '
        'uploadProgress is non-null', (tester) async {
      final progress = ValueNotifier<double>(0.7);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        wrap(
          FileBubble(
            fileName: 'report.pdf',
            mimeType: 'application/pdf',
            uploadProgress: progress,
          ),
        ),
      );

      expect(find.byIcon(Icons.picture_as_pdf), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disables tap-to-open while uploading', (tester) async {
      final progress = ValueNotifier<double>(0.7);
      addTearDown(progress.dispose);
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          FileBubble(
            fileName: 'report.pdf',
            uploadProgress: progress,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('report.pdf'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('shows the file-type icon again once uploadProgress clears', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const FileBubble(
            fileName: 'report.pdf',
            mimeType: 'application/pdf',
            uploadProgress: null,
          ),
        ),
      );

      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });
  });

  group('FileBubble — failed upload retry', () {
    testWidgets(
      'shows a retry icon instead of the file-type icon when failed and '
      'onRetry is wired',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            FileBubble(
              fileName: 'report.pdf',
              mimeType: 'application/pdf',
              isFailed: true,
              onRetry: () {},
            ),
          ),
        );

        expect(find.byIcon(Icons.picture_as_pdf), findsNothing);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      },
    );

    testWidgets('tapping the retry icon calls onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          FileBubble(
            fileName: 'report.pdf',
            isFailed: true,
            onRetry: () => retried = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh));
      expect(retried, isTrue);
    });

    testWidgets('disables tap-to-open once failed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          FileBubble(
            fileName: 'report.pdf',
            isFailed: true,
            onRetry: () {},
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('report.pdf'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets(
      'still marks the slot as failed when onRetry is not wired, with a '
      'static error glyph instead of a retry arrow that cannot work',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const FileBubble(
              fileName: 'report.pdf',
              mimeType: 'application/pdf',
              isFailed: true,
            ),
          ),
        );

        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byIcon(Icons.picture_as_pdf), findsNothing);
      },
    );

    testWidgets(
      'never shows the retry icon while an upload is still in flight, even '
      'when isFailed and onRetry are both set',
      (tester) async {
        final progress = ValueNotifier<double>(0.7);
        addTearDown(progress.dispose);
        await tester.pumpWidget(
          wrap(
            FileBubble(
              fileName: 'report.pdf',
              mimeType: 'application/pdf',
              uploadProgress: progress,
              isFailed: true,
              onRetry: () {},
            ),
          ),
        );

        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });
}
