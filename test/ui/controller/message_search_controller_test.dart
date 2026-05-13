import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final msg1 = ChatMessage(
    id: 'msg1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    text: 'Hello world',
  );

  final msg2 = ChatMessage(
    id: 'msg2',
    from: 'u2',
    timestamp: DateTime(2026, 1, 2),
    text: 'Hello again',
  );

  group('MessageSearchController', () {
    test('initial state is empty and not loading', () {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            const Success(PaginatedResponse(items: [], hasMore: false)),
      );
      expect(controller.query, isEmpty);
      expect(controller.results, isEmpty);
      expect(controller.isLoading, false);
      expect(controller.hasMore, false);
      controller.dispose();
    });

    test('search updates results', () async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg1, msg2], hasMore: false)),
      );

      await controller.search('hello', 'room1');

      expect(controller.query, 'hello');
      expect(controller.results, hasLength(2));
      expect(controller.isLoading, false);
      controller.dispose();
    });

    test('search with empty query clears results', () async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg1], hasMore: false)),
      );

      await controller.search('hello', 'room1');
      expect(controller.results, hasLength(1));

      await controller.search('', 'room1');
      expect(controller.results, isEmpty);
      expect(controller.isLoading, false);
      controller.dispose();
    });

    test('clear resets all state', () async {
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            Success(PaginatedResponse(items: [msg1], hasMore: true)),
      );

      await controller.search('hello', 'room1');
      controller.clear();

      expect(controller.query, isEmpty);
      expect(controller.results, isEmpty);
      expect(controller.hasMore, false);
      controller.dispose();
    });

    test('loadMore appends results', () async {
      var callCount = 0;
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async {
          callCount++;
          if (callCount == 1) {
            return Success(PaginatedResponse(items: [msg1], hasMore: true));
          }
          return Success(PaginatedResponse(items: [msg2], hasMore: false));
        },
      );

      await controller.search('hello', 'room1');
      expect(controller.results, hasLength(1));
      expect(controller.hasMore, true);

      await controller.loadMore();
      expect(controller.results, hasLength(2));
      expect(controller.hasMore, false);
      controller.dispose();
    });

    test('loadMore does nothing when hasMore is false', () async {
      var callCount = 0;
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async {
          callCount++;
          return const Success(PaginatedResponse(items: [], hasMore: false));
        },
      );

      await controller.search('hello', 'room1');
      expect(callCount, 1);

      await controller.loadMore();
      expect(callCount, 1);
      controller.dispose();
    });
  });
}
