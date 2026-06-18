import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(imagePickerChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(imagePickerChannel, null);
  });

  Future<AvatarPickerOutcome?> openSheet(
    WidgetTester tester, {
    String? initialAvatarUrl,
    bool allowRemove = true,
    AvatarKind kind = AvatarKind.user,
  }) async {
    AvatarPickerOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await AvatarPickerSheet.show(
                  context: context,
                  kind: kind,
                  initialAvatarUrl: initialAvatarUrl,
                  allowRemove: allowRemove,
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
    return outcome;
  }

  testWidgets('renders camera and gallery rows for a user avatar', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('View photo'), findsNothing);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('uses the group title for a room avatar', (tester) async {
    await openSheet(tester, kind: AvatarKind.room);

    expect(find.text('Group photo'), findsOneWidget);
  });

  testWidgets('shows view and remove rows when an avatar already exists', (
    tester,
  ) async {
    await openSheet(tester, initialAvatarUrl: 'https://cdn/a.jpg');

    expect(find.text('View photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
  });

  testWidgets('hides the remove row when allowRemove is false', (tester) async {
    await openSheet(
      tester,
      initialAvatarUrl: 'https://cdn/a.jpg',
      allowRemove: false,
    );

    expect(find.text('View photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('tapping Remove resolves to AvatarRemoved', (tester) async {
    AvatarPickerOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await AvatarPickerSheet.show(
                  context: context,
                  kind: AvatarKind.user,
                  initialAvatarUrl: 'https://cdn/a.jpg',
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

    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    expect(outcome, isA<AvatarRemoved>());
  });

  testWidgets('dismissing the sheet resolves to AvatarPickerCancelled', (
    tester,
  ) async {
    AvatarPickerOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await AvatarPickerSheet.show(
                  context: context,
                  kind: AvatarKind.user,
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

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(outcome, isA<AvatarPickerCancelled>());
  });

  testWidgets('tapping gallery with no platform picker yields cancelled', (
    tester,
  ) async {
    AvatarPickerOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await AvatarPickerSheet.show(
                  context: context,
                  kind: AvatarKind.user,
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

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(outcome, isA<AvatarPickerCancelled>());
  });
}
