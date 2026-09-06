import 'pagination.dart';
import 'result.dart';

/// Reads one offset-based page of a listing.
typedef ChatPageReader<T> =
    Future<ChatResult<ChatPaginatedResponse<T>>> Function(
      ChatPaginationParams pagination,
    );

/// Page size asked of a paginated listing. The backend caps `limit` at 100
/// and falls back to 50 when the parameter is missing, so the maximum keeps
/// a full read to as few round-trips as the contract allows.
const int chatListingPageSize = 100;

/// Hard stop for a full read, so a backend that keeps reporting `hasMore`
/// cannot spin the client forever. At [chatListingPageSize] per page this
/// covers 20 000 entries, far past any real account.
const int chatListingMaxPages = 200;

/// Reads [readPage] from [ChatPaginationParams.offset] `0` until the backend
/// stops reporting `hasMore`, and answers the concatenation of every page.
///
/// Every listing this SDK reads is paginated and applies a default `limit`
/// even when the request omits one, so a single response is a truncated view
/// of the set, never the whole of it. Callers that need the whole of it walk
/// it through here.
///
/// The first page that fails aborts the walk and is returned as the failure:
/// a partial set committed as if it were complete is what the walk exists to
/// prevent. An empty page ends the walk whatever `hasMore` claims — with
/// nothing to advance past, the next request would repeat the last one.
///
/// [isCancelled] is polled after every page so a caller that went away (a
/// disposed controller, an unmounted widget) stops paging; the walk then
/// answers `null` instead of a result, and the caller decides what a
/// cancelled read means for it.
Future<ChatResult<List<T>>?> readAllPages<T>(
  ChatPageReader<T> readPage, {
  int pageSize = chatListingPageSize,
  int maxPages = chatListingMaxPages,
  bool Function()? isCancelled,
}) async {
  final items = <T>[];
  var offset = 0;

  for (var page = 0; page < maxPages; page++) {
    final result = await readPage(
      ChatPaginationParams(limit: pageSize, offset: offset),
    );
    if (isCancelled?.call() ?? false) return null;
    if (result.isFailure) return result.castFailure<List<T>>();
    final chunk = result.dataOrThrow;
    items.addAll(chunk.items);
    if (!chunk.hasMore || chunk.items.isEmpty) break;
    offset += chunk.items.length;
  }

  return ChatSuccess(items);
}
