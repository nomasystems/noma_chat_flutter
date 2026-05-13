import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AttachmentPickerSheet', () {
    testWidgets('shows camera, gallery, and file options', (tester) async {
      await tester.pumpWidget(wrap(AttachmentPickerSheet(
        onPickCamera: () {},
        onPickGallery: () {},
        onPickFile: () {},
      )));

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('shows correct icons', (tester) async {
      await tester.pumpWidget(wrap(AttachmentPickerSheet(
        onPickCamera: () {},
        onPickGallery: () {},
        onPickFile: () {},
      )));

      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.byIcon(Icons.photo_library), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets('uses custom labels', (tester) async {
      await tester.pumpWidget(wrap(const AttachmentPickerSheet(
        cameraLabel: 'Take Photo',
        galleryLabel: 'Choose Photo',
        fileLabel: 'Document',
      )));

      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose Photo'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
    });

    testWidgets('calls onPickCamera and closes sheet', (tester) async {
      var cameraCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => AttachmentPickerSheet(
                    onPickCamera: () => cameraCalled = true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(cameraCalled, true);
    });

    testWidgets('calls onPickGallery and closes sheet', (tester) async {
      var galleryCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => AttachmentPickerSheet(
                    onPickGallery: () => galleryCalled = true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.photo_library));
      await tester.pumpAndSettle();

      expect(galleryCalled, true);
    });

    testWidgets('calls onPickFile and closes sheet', (tester) async {
      var fileCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => AttachmentPickerSheet(
                    onPickFile: () => fileCalled = true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.insert_drive_file));
      await tester.pumpAndSettle();

      expect(fileCalled, true);
    });

    testWidgets('static show method displays bottom sheet', (tester) async {
      var cameraCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AttachmentPickerSheet.show(
                  context,
                  onPickCamera: () => cameraCalled = true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(AttachmentPickerSheet), findsOneWidget);

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(cameraCalled, true);
    });
  });
}
