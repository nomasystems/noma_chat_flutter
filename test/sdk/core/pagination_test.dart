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
          cursor: 'b64-prev-token',
          direction: ChatCursorDirection.older,
          limit: 50,
        ).toQueryParams(),
        {'cursor': 'b64-prev-token', 'direction': 'older', 'limit': 50},
      );
    });

    test('newer direction emits direction=newer', () {
      expect(
        const ChatCursorPaginationParams(
          cursor: 'b64-next-token',
          direction: ChatCursorDirection.newer,
        ).toQueryParams(),
        {'cursor': 'b64-next-token', 'direction': 'newer'},
      );
    });

    test('cursor without a direction omits direction', () {
      expect(
        const ChatCursorPaginationParams(cursor: 'b64-token').toQueryParams(),
        {'cursor': 'b64-token'},
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

    test('toString includes count, hasMore, totalCount and cursors', () {
      const r = ChatPaginatedResponse<int>(
        items: [1, 2],
        hasMore: true,
        totalCount: 5,
        nextCursor: 'n1',
        prevCursor: 'p1',
      );
      expect(
        r.toString(),
        'ChatPaginatedResponse(2 items, hasMore: true, totalCount: 5, '
        'nextCursor: n1, prevCursor: p1)',
      );
    });

    test('equality distinguishes nextCursor and prevCursor', () {
      const base = ChatPaginatedResponse<int>(
        items: [1],
        hasMore: true,
        nextCursor: 'n',
        prevCursor: 'p',
      );
      const sameCursors = ChatPaginatedResponse<int>(
        items: [1],
        hasMore: true,
        nextCursor: 'n',
        prevCursor: 'p',
      );
      const differentNext = ChatPaginatedResponse<int>(
        items: [1],
        hasMore: true,
        nextCursor: 'n2',
        prevCursor: 'p',
      );
      const differentPrev = ChatPaginatedResponse<int>(
        items: [1],
        hasMore: true,
        nextCursor: 'n',
        prevCursor: 'p2',
      );

      expect(base, sameCursors);
      expect(base.hashCode, sameCursors.hashCode);
      expect(base, isNot(differentNext));
      expect(base, isNot(differentPrev));
    });

    test('map() preserves nextCursor and prevCursor', () {
      const src = ChatPaginatedResponse<int>(
        items: [1, 2],
        hasMore: true,
        totalCount: 9,
        nextCursor: 'n',
        prevCursor: 'p',
      );

      final out = src.map((i) => 'v$i');

      expect(out.items, ['v1', 'v2']);
      expect(out.nextCursor, 'n');
      expect(out.prevCursor, 'p');
    });
  });
}
