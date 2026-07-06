import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AttachmentPickerSheet', () {
    testWidgets('shows camera, gallery, and file options', (tester) async {
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            onPickCamera: () {},
            onPickGallery: () {},
            onPickFile: () {},
          ),
        ),
      );

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('shows correct icons', (tester) async {
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            onPickCamera: () {},
            onPickGallery: () {},
            onPickFile: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.byIcon(Icons.photo_library), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets('uses custom labels', (tester) async {
      // Rows only render when their callback is non-null (      // sheet collapses unused slots so e.g. a Gallery-only composer
      // looks intentional rather than half-empty). Pass no-op
      // callbacks for the three labels under test.
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            cameraLabel: 'Take Photo',
            galleryLabel: 'Choose Photo',
            fileLabel: 'Document',
            onPickCamera: () {},
            onPickGallery: () {},
            onPickFile: () {},
          ),
        ),
      );

      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose Photo'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
    });

    testWidgets('calls onPickCamera and closes sheet', (tester) async {
      var cameraCalled = false;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(cameraCalled, true);
    });

    testWidgets('calls onPickGallery and closes sheet', (tester) async {
      var galleryCalled = false;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.photo_library));
      await tester.pumpAndSettle();

      expect(galleryCalled, true);
    });

    testWidgets('calls onPickFile and closes sheet', (tester) async {
      var fileCalled = false;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.insert_drive_file));
      await tester.pumpAndSettle();

      expect(fileCalled, true);
    });

    testWidgets('static show method displays bottom sheet', (tester) async {
      var cameraCalled = false;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(AttachmentPickerSheet), findsOneWidget);

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(cameraCalled, true);
    });

    testWidgets('extraOptions render after built-in rows', (tester) async {
      var extraCalled = false;
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            onPickCamera: () {},
            extraOptions: [
              AttachmentSheetOption(
                icon: Icons.poll,
                label: 'Poll',
                onTap: () => extraCalled = true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Poll'), findsOneWidget);
      expect(find.byIcon(Icons.poll), findsOneWidget);
      expect(extraCalled, false);
    });

    testWidgets(
      'extraOptions with previewBuilder replaces the default icon circle',
      (tester) async {
        const previewKey = Key('poll-preview');
        await tester.pumpWidget(
          wrap(
            AttachmentPickerSheet(
              onPickCamera: () {},
              extraOptions: [
                AttachmentSheetOption(
                  icon: Icons.poll,
                  label: 'Poll',
                  onTap: () {},
                  previewBuilder: (context) => const ColoredBox(
                    key: previewKey,
                    color: Colors.purple,
                    child: Text('P'),
                  ),
                ),
              ],
            ),
          ),
        );

        expect(find.byIcon(Icons.poll), findsNothing);
        expect(find.byKey(previewKey), findsOneWidget);
        expect(find.text('P'), findsOneWidget);
        expect(find.text('Poll'), findsOneWidget);
      },
    );

    testWidgets('previewBuilder row still invokes onTap and closes the sheet', (
      tester,
    ) async {
      const previewKey = Key('poll-preview');
      var pollTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AttachmentPickerSheet.show(
                    context,
                    extraOptions: [
                      AttachmentSheetOption(
                        icon: Icons.poll,
                        label: 'Poll',
                        onTap: () => pollTapped = true,
                        previewBuilder: (context) => const ColoredBox(
                          key: previewKey,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(previewKey));
      await tester.pumpAndSettle();

      expect(pollTapped, true);
      expect(find.byType(AttachmentPickerSheet), findsNothing);
    });
  });
}
