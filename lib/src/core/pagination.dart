/// Offset-based pagination parameters.
class PaginationParams {
  final int? limit;
  final int? offset;
  final String? sort;
  final SortOrder? order;

  const PaginationParams({this.limit, this.offset, this.sort, this.order});

  Map<String, dynamic> toQueryParams() => {
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
    if (sort != null) 'sort': sort,
    if (order != null) 'order': order!.name,
  };
}

/// Cursor-based pagination using before/after timestamps (ISO 8601).
class CursorPaginationParams {
  final String? before;
  final String? after;
  final int? limit;

  const CursorPaginationParams({this.before, this.after, this.limit});

  Map<String, dynamic> toQueryParams() => {
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    if (limit != null) 'limit': limit,
  };
}

/// A page of results with a flag indicating whether more data is available.
class PaginatedResponse<T> {
  final List<T> items;
  final bool hasMore;
  final int? totalCount;

  const PaginatedResponse({
    required this.items,
    required this.hasMore,
    this.totalCount,
  });

  PaginatedResponse<R> map<R>(R Function(T item) transform) =>
      PaginatedResponse(
        items: items.map(transform).toList(),
        hasMore: hasMore,
        totalCount: totalCount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaginatedResponse<T> &&
          other.hasMore == hasMore &&
          other.totalCount == totalCount &&
          _listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll([...items, hasMore, totalCount]);

  @override
  String toString() =>
      'PaginatedResponse(${items.length} items, hasMore: $hasMore, totalCount: $totalCount)';
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
enum SortOrder { asc, desc }
