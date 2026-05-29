import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Widget tests for [ProfileSettingsPage] — the "my profile" editor.
///
/// `currentUser` is seeded into the mock as well, so the on-mount
/// `_refreshFromBackend` (a `users.get`) returns the same record and does
/// not clobber the pre-filled fields.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Mara', bio: 'My bio');
  final l10n = ChatTheme.defaults.l10n;

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    // Keep the backend record identical to currentUser so the refresh is
    // a no-op for the tracked fields.
    client.seedUser(me);
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Widget host({bool showEmail = false, bool showBio = true}) => MaterialApp(
    home: ProfileSettingsPage(
      adapter: adapter,
      showEmail: showEmail,
      showBio: showBio,
    ),
  );

  IconButton saveButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check));

  group('ProfileSettingsPage — render', () {
    testWidgets('renders the title and the name + bio fields prefilled', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text(l10n.profile), findsOneWidget);
      expect(find.text(l10n.yourName), findsOneWidget);
      expect(find.text(l10n.about), findsOneWidget);
      // Current values are pre-filled into the editable fields.
      expect(find.text('Mara'), findsOneWidget);
      expect(find.text('My bio'), findsOneWidget);
    });

    testWidgets('hides the bio field when showBio is false', (tester) async {
      await tester.pumpWidget(host(showBio: false));
      await tester.pumpAndSettle();

      expect(find.text(l10n.about), findsNothing);
    });

    testWidgets('shows the email field only when showEmail is true', (
      tester,
    ) async {
      await tester.pumpWidget(host(showEmail: true));
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
    });
  });

  group('ProfileSettingsPage — save gating', () {
    testWidgets('save is disabled until a field changes', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('editing the name enables save', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Renamed');
      await tester.pump();

      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('clearing the name to an invalid value keeps save disabled', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ab');
      await tester.pump();

      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('editing the bio enables save', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Bio is the second field.
      await tester.enterText(find.byType(TextField).at(1), 'Updated bio');
      await tester.pump();

      expect(saveButton(tester).onPressed, isNotNull);
    });
  });

  group('ProfileSettingsPage — submission', () {
    testWidgets('saving a valid edit persists and surfaces a confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Renamed');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Success toast shown and, with originals updated, save re-disables.
      expect(find.text(l10n.changesSaved), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
    });
  });
}
