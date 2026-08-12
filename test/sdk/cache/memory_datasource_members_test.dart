import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';

void main() {
  late MemoryChatLocalDatasource ds;

  setUp(() => ds = MemoryChatLocalDatasource());

  ChatPaginatedResponse<RoomUser> page(List<String> ids) =>
      ChatPaginatedResponse(
        items: [for (final id in ids) RoomUser(userId: id)],
        hasMore: false,
        totalCount: ids.length,
      );

  test('a roster round-trips', () async {
    await ds.saveRoomMembers('r1', page(['me', 'bob']));

    final stored = (await ds.getRoomMembers('r1')).dataOrThrow!;

    expect(stored.items.map((m) => m.userId), ['me', 'bob']);
    expect(stored.totalCount, 2);
  });

  test('a room with no record reads back null, not an empty roster', () async {
    expect((await ds.getRoomMembers('never')).dataOrThrow, isNull);
  });

  test('deleteRoomMembers drops just that room', () async {
    await ds.saveRoomMembers('r1', page(['bob']));
    await ds.saveRoomMembers('r2', page(['zoe']));

    await ds.deleteRoomMembers('r1');

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
    expect((await ds.getRoomMembers('r2')).dataOrThrow!.items, hasLength(1));
  });

  test('deleteRoom cascades to the roster', () async {
    await ds.saveRoomMembers('r1', page(['bob']));

    await ds.deleteRoom('r1');

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
  });

  test('clear() wipes the rosters too', () async {
    await ds.saveRoomMembers('r1', page(['bob']));

    await ds.clear();

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
  });
}
