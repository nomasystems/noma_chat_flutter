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

/// Direction for bidirectional cursor pagination.
///
/// * [older] — load older history: messages BEFORE the [cursor], anchored on
///   the [ChatPaginatedResponse.prevCursor] of the page you already hold.
/// * [newer] — catch up: messages AFTER the [cursor], anchored on the
///   [ChatPaginatedResponse.nextCursor] of the page you already hold. This is
///   the backend default when [ChatCursorPaginationParams.direction] is unset.
enum ChatCursorDirection { older, newer }

/// Cursor-based pagination.
///
/// Paging is driven by an **opaque** [cursor] (base64) emitted by the backend
/// as either [ChatPaginatedResponse.prevCursor] (anchored on the oldest
/// message of a page) or [ChatPaginatedResponse.nextCursor] (anchored on the
/// newest message of a page). The cursor is seq-based server-side, so it is
/// immune to the identical-timestamp skip/replay bug that timestamp paging
/// suffered from.
///
/// * To load older history pass the stored [ChatPaginatedResponse.prevCursor]
///   as [cursor] together with `direction: ChatCursorDirection.older`.
/// * To catch up on newer messages pass the stored
///   [ChatPaginatedResponse.nextCursor] as [cursor] together with
///   `direction: ChatCursorDirection.newer` (or leave [direction] unset — the
///   backend defaults to `newer`).
class ChatCursorPaginationParams {
  final int? limit;
  final int? offset;

  /// Opaque pagination cursor echoed back from
  /// [ChatPaginatedResponse.prevCursor] (older anchor) or
  /// [ChatPaginatedResponse.nextCursor] (newer anchor). The backend resumes
  /// from the exact seq-based position the cursor encodes.
  final String? cursor;

  /// Travel direction relative to [cursor]. `null` lets the backend apply its
  /// default (`newer`). Emitted as the `direction` query param (`older` /
  /// `newer`) when set.
  final ChatCursorDirection? direction;

  const ChatCursorPaginationParams({
    this.limit,
    this.offset,
    this.cursor,
    this.direction,
  });

  Map<String, dynamic> toQueryParams() => {
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
    if (cursor != null) 'cursor': cursor,
    if (direction != null) 'direction': direction!.name,
  };
}

/// A page of results with a flag indicating whether more data is available.
class ChatPaginatedResponse<T> {
  final List<T> items;
  final bool hasMore;
  final int? totalCount;

  /// Opaque cursor for the NEWER page, parsed from the response `next` field
  /// and anchored on the newest message of this page. `null` when the backend
  /// reports no newer page. Feed it back via [ChatCursorPaginationParams.cursor]
  /// with `direction: ChatCursorDirection.newer` to catch up.
  final String? nextCursor;

  /// Opaque cursor for the OLDER page, parsed from the response `prev` field
  /// and anchored on the oldest message of this page. `null` when the backend
  /// reports no older history. Feed it back via
  /// [ChatCursorPaginationParams.cursor] with `direction: ChatCursorDirection.older`
  /// to load older history.
  final String? prevCursor;

  const ChatPaginatedResponse({
    required this.items,
    required this.hasMore,
    this.totalCount,
    this.nextCursor,
    this.prevCursor,
  });

  ChatPaginatedResponse<R> map<R>(R Function(T item) transform) =>
      ChatPaginatedResponse(
        items: items.map(transform).toList(),
        hasMore: hasMore,
        totalCount: totalCount,
        nextCursor: nextCursor,
        prevCursor: prevCursor,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPaginatedResponse<T> &&
          other.hasMore == hasMore &&
          other.totalCount == totalCount &&
          other.nextCursor == nextCursor &&
          other.prevCursor == prevCursor &&
          _listEquals(other.items, items);

  @override
  int get hashCode =>
      Object.hashAll([...items, hasMore, totalCount, nextCursor, prevCursor]);

  @override
  String toString() =>
      'ChatPaginatedResponse(${items.length} items, hasMore: $hasMore, '
      'totalCount: $totalCount, nextCursor: $nextCursor, '
      'prevCursor: $prevCursor)';
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
