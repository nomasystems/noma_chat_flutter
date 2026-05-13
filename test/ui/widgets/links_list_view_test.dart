import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  ChatMessage msg(
    String id, {
    String? text,
    DateTime? timestamp,
    String from = 'u1',
    bool isDeleted = false,
    bool isSystem = false,
  }) => ChatMessage(
    id: id,
    from: from,
    timestamp: timestamp ?? DateTime(2025, 1, 1),
    text: text,
    isDeleted: isDeleted,
    isSystem: isSystem,
  );

  group('LinksListView.extract', () {
    test('extracts URLs from messages', () {
      final links = LinksListView.extract([
        msg('1', text: 'mira esto https://flutter.dev'),
        msg('2', text: 'sin links aquí'),
        msg('3', text: 'http://example.com y http://otro.com'),
      ]);
      expect(
        links.map((l) => l.url),
        containsAll([
          'https://flutter.dev',
          'http://example.com',
          'http://otro.com',
        ]),
      );
    });

    test('skips deleted and system messages', () {
      final links = LinksListView.extract([
        msg('1', text: 'https://a.com', isDeleted: true),
        msg('2', text: 'https://b.com', isSystem: true),
        msg('3', text: 'https://c.com'),
      ]);
      expect(links.map((l) => l.url), ['https://c.com']);
    });

    test('deduplicates repeated URLs (keeps first occurrence)', () {
      final links = LinksListView.extract([
        msg('1', text: 'https://x.com', timestamp: DateTime(2025, 1, 1)),
        msg('2', text: 'https://x.com again', timestamp: DateTime(2025, 1, 2)),
      ]);
      expect(links, hasLength(1));
      expect(links.first.messageId, '1');
    });

    test('sorts by timestamp desc', () {
      final links = LinksListView.extract([
        msg('1', text: 'https://old.com', timestamp: DateTime(2025, 1, 1)),
        msg('2', text: 'https://new.com', timestamp: DateTime(2025, 1, 5)),
        msg('3', text: 'https://mid.com', timestamp: DateTime(2025, 1, 3)),
      ]);
      expect(links.map((l) => l.url), [
        'https://new.com',
        'https://mid.com',
        'https://old.com',
      ]);
    });

    test('messages without text produce no links', () {
      final links = LinksListView.extract([msg('1')]);
      expect(links, isEmpty);
    });
  });

  group('LinksListView widget', () {
    testWidgets('shows empty state when no links', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinksListView(messages: [msg('1', text: 'no links here')]),
          ),
        ),
      );
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('renders the extracted links', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinksListView(
              messages: [msg('1', text: 'visit https://flutter.dev')],
            ),
          ),
        ),
      );
      expect(find.text('https://flutter.dev'), findsOneWidget);
    });

    testWidgets('invokes onTapLink', (tester) async {
      SharedLink? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinksListView(
              messages: [msg('1', text: 'https://example.com')],
              onTapLink: (link) => tapped = link,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ListTile));
      expect(tapped?.url, 'https://example.com');
    });
  });
}
