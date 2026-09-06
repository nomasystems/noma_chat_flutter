import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/core/pagination_walk.dart';

/// Serves [rowCount] rows the way the backend does: `limit` capped at 100 and
/// `offset` clamped to [chatListingMaxOffset], so a request past the cap
/// answers with the last reachable page instead of advancing.
class _ClampingListing {
  final int rowCount;
  final List<int> offsets = [];

  _ClampingListing({required this.rowCount});

  Future<ChatResult<ChatPaginatedResponse<String>>> read(
    ChatPaginationParams pagination,
  ) async {
    final requested = pagination.offset ?? 0;
    offsets.add(requested);
    final limit = (pagination.limit ?? 50).clamp(1, 100);
    final start = requested.clamp(0, chatListingMaxOffset).clamp(0, rowCount);
    final end = (start + limit).clamp(0, rowCount);
    return ChatSuccess(
      ChatPaginatedResponse(
        items: [for (var i = start; i < end; i++) 'row-$i'],
        hasMore: end < rowCount,
      ),
    );
  }
}

void main() {
  group('readAllPages', () {
    test('the page cap matches the highest offset the backend honours', () {
      expect(chatListingMaxOffset, 10000);
      expect(chatListingMaxPages, 101);
      expect(
        (chatListingMaxPages - 1) * chatListingPageSize,
        chatListingMaxOffset,
        reason: 'the last page the walk can reach starts at the offset cap',
      );
    });

    test('walks every page of a set that fits under the cap', () async {
      final listing = _ClampingListing(rowCount: 250);

      final result = await readAllPages<String>(listing.read);

      expect(result!.dataOrThrow.length, 250);
      expect(listing.offsets, [0, 100, 200]);
    });

    test('stops at the offset cap instead of repeating its page', () async {
      final listing = _ClampingListing(rowCount: 10150);

      final result = await readAllPages<String>(listing.read);

      expect(
        listing.offsets.length,
        101,
        reason: 'offsets 0 to 10000 in steps of 100 is every page there is',
      );
      expect(listing.offsets.last, chatListingMaxOffset);
      expect(
        listing.offsets.toSet().length,
        listing.offsets.length,
        reason: 'no offset is asked for twice',
      );
      expect(result!.dataOrThrow.length, 10100);
    });
  });
}
