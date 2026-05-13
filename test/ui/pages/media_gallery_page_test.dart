import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Empty-flow tests for [MediaGalleryPage]. The mock client returns an
/// empty page, so the widget settles into the empty state for every tab —
/// enough to exercise the load path, the three tab builders and the dispose
/// path of the `TabController`. Network-backed scenarios are covered
/// indirectly via the `attachments` API tests.
void main() {
  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGalleryPage(client: client, roomId: 'room-1'),
      ),
    );
    // The page runs `_load` in initState; pumpAndSettle drains it.
    await tester.pumpAndSettle();
  }

  testWidgets('renders the gallery scaffold with three tabs', (tester) async {
    await pumpPage(tester);

    expect(find.byType(MediaGalleryPage), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(3));
  });

  testWidgets('settles into empty state when there are no attachments', (
    tester,
  ) async {
    await pumpPage(tester);

    // Loading indicator dismissed and Media tab is empty.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Docs tab shows its empty state', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Links tab shows its empty state when no link source messages', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Tab).at(2));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Links tab finds URLs in linkSourceMessages', (tester) async {
    final messages = [
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'check this out https://example.com/path',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaGalleryPage(
          client: client,
          roomId: 'room-1',
          linkSourceMessages: messages,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Tab).at(2));
    await tester.pumpAndSettle();

    expect(find.byType(LinksListView), findsOneWidget);
  });

  testWidgets('dispose releases the TabController without throwing', (
    tester,
  ) async {
    await pumpPage(tester);
    // Replacing the widget tree forces dispose of the page state.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });
}
