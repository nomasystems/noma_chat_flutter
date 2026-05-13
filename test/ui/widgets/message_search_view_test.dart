import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final msg1 = ChatMessage(
    id: 'msg1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    text: 'Hello world',
  );

  group('MessageSearchView', () {
    testWidgets('renders search input with hint', (tester) async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            const Success(PaginatedResponse(items: [], hasMore: false)),
      );

      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'room1')),
      );

      expect(find.text('Search messages'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows results after search', (tester) async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg1], hasMore: false)),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            senderNameResolver: (id) => id == 'u1' ? 'Alice' : id,
          ),
        ),
      );

      await controller.search('hello', 'room1');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows no results state', (tester) async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            const Success(PaginatedResponse(items: [], hasMore: false)),
      );

      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'room1')),
      );

      await controller.search('nonexistent', 'room1');
      await tester.pump();

      expect(find.text('No results'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('highlights the query inside the result text', (tester) async {
      final msg = ChatMessage(
        id: 'msg1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'The quick brown fox',
      );
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg], hasMore: false)),
      );

      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'room1')),
      );

      await controller.search('Quick', 'room1');
      await tester.pump();

      final matches = <TextSpan>[];
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == 'quick') matches.add(span);
          if (span.children != null) span.children!.forEach(visit);
        }
      }

      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        visit(rt.text);
      }
      expect(
        matches,
        isNotEmpty,
        reason: 'expected a span with text "quick" (case-folded match)',
      );
      expect(matches.first.style?.fontWeight, FontWeight.w700);
      controller.dispose();
    });

    testWidgets('tapping result calls onMessageTap', (tester) async {
      String? tappedRoomId;
      String? tappedMessageId;

      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg1], hasMore: false)),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            onMessageTap: (roomId, messageId) {
              tappedRoomId = roomId;
              tappedMessageId = messageId;
            },
          ),
        ),
      );

      await controller.search('hello', 'room1');
      await tester.pump();

      await tester.tap(find.text('Hello world'));
      expect(tappedRoomId, 'room1');
      expect(tappedMessageId, 'msg1');
      controller.dispose();
    });
  });
}
