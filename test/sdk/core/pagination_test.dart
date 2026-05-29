import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatPaginationParams.toQueryParams', () {
    test('omits null fields', () {
      expect(const ChatPaginationParams().toQueryParams(), <String, dynamic>{});
    });

    test('emits set fields, including order.name', () {
      expect(
        const ChatPaginationParams(
          limit: 20,
          offset: 40,
          sort: 'createdAt',
          order: ChatSortOrder.desc,
        ).toQueryParams(),
        {'limit': 20, 'offset': 40, 'sort': 'createdAt', 'order': 'desc'},
      );
    });
  });

  group('ChatCursorPaginationParams.toQueryParams', () {
    test('omits null fields', () {
      expect(
        const ChatCursorPaginationParams().toQueryParams(),
        <String, dynamic>{},
      );
    });

    test('emits only the set ones', () {
      expect(
        const ChatCursorPaginationParams(
          before: '2026-01-01T00:00:00Z',
          limit: 50,
        ).toQueryParams(),
        {'before': '2026-01-01T00:00:00Z', 'limit': 50},
      );
    });
  });

  group('ChatPaginatedResponse', () {
    test('equality compares items, hasMore and totalCount', () {
      const a = ChatPaginatedResponse<int>(items: [1, 2], hasMore: true);
      const b = ChatPaginatedResponse<int>(items: [1, 2], hasMore: true);
      const c = ChatPaginatedResponse<int>(items: [1, 3], hasMore: true);
      const d = ChatPaginatedResponse<int>(items: [1, 2], hasMore: false);
      const e = ChatPaginatedResponse<int>(
        items: [1, 2],
        hasMore: true,
        totalCount: 99,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a, isNot(e));
    });

    test('identical short-circuits ==', () {
      const a = ChatPaginatedResponse<int>(items: [], hasMore: false);
      expect(identical(a, a), true);
      expect(a == a, true);
    });

    test('map() transforms items keeping hasMore + totalCount', () {
      const src = ChatPaginatedResponse<int>(
        items: [1, 2, 3],
        hasMore: true,
        totalCount: 42,
      );

      final out = src.map((i) => 'v$i');

      expect(out.items, ['v1', 'v2', 'v3']);
      expect(out.hasMore, true);
      expect(out.totalCount, 42);
    });

    test('toString includes count, hasMore and totalCount', () {
      const r = ChatPaginatedResponse<int>(
        items: [1, 2],
        hasMore: true,
        totalCount: 5,
      );
      expect(
        r.toString(),
        'ChatPaginatedResponse(2 items, hasMore: true, totalCount: 5)',
      );
    });
  });
}
