/// Offset-based pagination parameters.
class ChatPaginationParams {
  final int? limit;
  final int? offset;
  final String? sort;
  final ChatSortOrder? order;

  const ChatPaginationParams({this.limit, this.offset, this.sort, this.order});

  Map<String, dynamic> toQueryParams() => {
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
    if (sort != null) 'sort': sort,
    if (order != null) 'order': order!.name,
  };
}

/// Cursor-based pagination using before/after timestamps (ISO 8601).
class ChatCursorPaginationParams {
  final String? before;
  final String? after;
  final int? limit;

  const ChatCursorPaginationParams({this.before, this.after, this.limit});

  Map<String, dynamic> toQueryParams() => {
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    if (limit != null) 'limit': limit,
  };
}

/// A page of results with a flag indicating whether more data is available.
class ChatPaginatedResponse<T> {
  final List<T> items;
  final bool hasMore;
  final int? totalCount;

  const ChatPaginatedResponse({
    required this.items,
    required this.hasMore,
    this.totalCount,
  });

  ChatPaginatedResponse<R> map<R>(R Function(T item) transform) =>
      ChatPaginatedResponse(
        items: items.map(transform).toList(),
        hasMore: hasMore,
        totalCount: totalCount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPaginatedResponse<T> &&
          other.hasMore == hasMore &&
          other.totalCount == totalCount &&
          _listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll([...items, hasMore, totalCount]);

  @override
  String toString() =>
      'ChatPaginatedResponse(${items.length} items, hasMore: $hasMore, totalCount: $totalCount)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Ordering hint for paginated queries. Most message and room listings use
/// `desc` (newest first) by default.
enum ChatSortOrder { asc, desc }
