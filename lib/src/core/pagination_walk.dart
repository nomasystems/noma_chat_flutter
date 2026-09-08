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

/// Highest `offset` the backend honours. Anything above it is clamped back
/// down to this value, so a request past the cap answers with the page just
/// read instead of advancing.
const int chatListingMaxOffset = 10000;

/// Hard stop for a full read, so a backend that keeps reporting `hasMore`
/// cannot spin the client forever. The last page the walk can reach starts at
/// [chatListingMaxOffset], so at [chatListingPageSize] per page this covers
/// 10 100 entries, far past any real account.
const int chatListingMaxPages = chatListingMaxOffset ~/ chatListingPageSize + 1;

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
/// nothing to advance past, the next request would repeat the last one. So
/// does an offset past [maxOffset]: the backend clamps it back down, so every
/// further request would answer with the page just read.
///
/// [isCancelled] is polled after every page so a caller that went away (a
/// disposed controller, an unmounted widget) stops paging; the walk then
/// answers `null` instead of a result, and the caller decides what a
/// cancelled read means for it.
Future<ChatResult<List<T>>?> readAllPages<T>(
  ChatPageReader<T> readPage, {
  int pageSize = chatListingPageSize,
  int maxPages = chatListingMaxPages,
  int maxOffset = chatListingMaxOffset,
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
    if (offset > maxOffset) break;
  }

  return ChatSuccess(items);
}
