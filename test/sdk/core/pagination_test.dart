import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('PaginationParams.toQueryParams', () {
    test('omits null fields', () {
      expect(const PaginationParams().toQueryParams(), <String, dynamic>{});
    });

    test('emits set fields, including order.name', () {
      expect(
        const PaginationParams(
          limit: 20,
          offset: 40,
          sort: 'createdAt',
          order: SortOrder.desc,
        ).toQueryParams(),
        {
          'limit': 20,
          'offset': 40,
          'sort': 'createdAt',
          'order': 'desc',
        },
      );
    });
  });

  group('CursorPaginationParams.toQueryParams', () {
    test('omits null fields', () {
      expect(const CursorPaginationParams().toQueryParams(),
          <String, dynamic>{});
    });

    test('emits only the set ones', () {
      expect(
        const CursorPaginationParams(
                before: '2026-01-01T00:00:00Z', limit: 50)
            .toQueryParams(),
        {'before': '2026-01-01T00:00:00Z', 'limit': 50},
      );
    });
  });

  group('PaginatedResponse', () {
    test('equality compares items, hasMore and totalCount', () {
      const a = PaginatedResponse<int>(items: [1, 2], hasMore: true);
      const b = PaginatedResponse<int>(items: [1, 2], hasMore: true);
      const c = PaginatedResponse<int>(items: [1, 3], hasMore: true);
      const d = PaginatedResponse<int>(items: [1, 2], hasMore: false);
      const e = PaginatedResponse<int>(
          items: [1, 2], hasMore: true, totalCount: 99);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a, isNot(e));
    });

    test('identical short-circuits ==', () {
      const a = PaginatedResponse<int>(items: [], hasMore: false);
      expect(identical(a, a), true);
      expect(a == a, true);
    });

    test('map() transforms items keeping hasMore + totalCount', () {
      const src = PaginatedResponse<int>(
          items: [1, 2, 3], hasMore: true, totalCount: 42);

      final out = src.map((i) => 'v$i');

      expect(out.items, ['v1', 'v2', 'v3']);
      expect(out.hasMore, true);
      expect(out.totalCount, 42);
    });

    test('toString includes count, hasMore and totalCount', () {
      const r = PaginatedResponse<int>(
          items: [1, 2], hasMore: true, totalCount: 5);
      expect(r.toString(), 'PaginatedResponse(2 items, hasMore: true, totalCount: 5)');
    });
  });
}
