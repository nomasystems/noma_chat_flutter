import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

ChatPaginatedResponse<RoomUser> page(
  List<RoomUser> items, {
  bool hasMore = false,
  int? totalCount,
}) => ChatPaginatedResponse(
  items: items,
  hasMore: hasMore,
  totalCount: totalCount,
);

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_members_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a roster round-trips with its roles, expansion fields and paging '
      'flags intact', () async {
    await ds.saveRoomMembers(
      'r1',
      page(
        const [
          RoomUser(userId: 'me', role: RoomRole.owner),
          RoomUser(
            userId: 'bob',
            role: RoomRole.admin,
            displayName: 'Bob',
            avatarUrl: 'https://cdn/bob.png',
          ),
          RoomUser(userId: 'zoe'),
        ],
        hasMore: true,
        totalCount: 42,
      ),
    );

    final stored = (await ds.getRoomMembers('r1')).dataOrThrow!;

    expect(stored.items.map((m) => m.userId), ['me', 'bob', 'zoe']);
    expect(stored.items[0].role, RoomRole.owner);
    expect(stored.items[1].role, RoomRole.admin);
    expect(stored.items[1].displayName, 'Bob');
    expect(stored.items[1].avatarUrl, 'https://cdn/bob.png');
    expect(stored.items[2].role, RoomRole.member);
    expect(stored.hasMore, isTrue);
    expect(stored.totalCount, 42);
  });

  test('the roles land on disk in their WIRE vocabulary, so a roster read '
      'back cannot be told from a freshly fetched one', () async {
    await ds.saveRoomMembers(
      'r1',
      page(const [
        RoomUser(userId: 'me', role: RoomRole.owner),
        RoomUser(userId: 'bob', role: RoomRole.admin),
        RoomUser(userId: 'zoe'),
      ]),
    );

    final box = await Hive.openBox<Map<dynamic, dynamic>>('chat_room_members');
    final rows = (box.get('r1')!['items'] as List)
        .cast<Map<dynamic, dynamic>>();

    // The backend's word for `member` is "user". Writing `role.name`
    // instead round-trips through this same file's own reader and would
    // look correct from the outside, while filling the box with a
    // vocabulary no other reader of this SDK speaks.
    expect(rows.map((r) => r['role']), ['owner', 'admin', 'user']);
  });

  test('a room that was never stored reads back as "no record", not as an '
      'empty roster', () async {
    expect((await ds.getRoomMembers('never')).dataOrThrow, isNull);
  });

  test('an unknown role degrades to member instead of making the whole '
      'roster unreadable', () async {
    final box = await Hive.openBox<Map<dynamic, dynamic>>('chat_room_members');
    await box.put('r1', {
      'items': [
        {'userId': 'bob', 'role': 'archduke'},
      ],
      'hasMore': false,
    });

    final stored = (await ds.getRoomMembers('r1')).dataOrThrow!;

    expect(stored.items.single.userId, 'bob');
    expect(stored.items.single.role, RoomRole.member);
  });

  test('a store that turns out to belong to somebody else takes the '
      'rosters with it', () async {
    // The roster box is the one that persists THIRD parties: userIds,
    // display names and avatars of people the account was in a room with.
    // A store found stamped for another user is destroyed rather than
    // served, and that wipe walks the registered global boxes — a box
    // missing from that register survives the wipe and hands the previous
    // owner's contacts to the next account on the device. `clear()` does
    // NOT cover this: it reaches the box by another route entirely.
    await ds.dispose();
    await Hive.close();

    var scoped = await HiveChatDatasource.create(
      basePath: tempDir.path,
      userId: 'alice',
    );
    await scoped.saveRoomMembers(
      'r1',
      page(const [RoomUser(userId: 'bob', displayName: 'Bob')]),
    );
    await scoped.dispose();
    await Hive.close();

    Hive.init(tempDir.path);
    final meta = await Hive.openBox<Map>(
      HiveChatDatasource.physicalBoxName('chat_meta', userId: 'alice'),
    );
    await meta.put('cacheOwner', {'userId': 'mallory'});
    await Hive.close();

    scoped = await HiveChatDatasource.create(
      basePath: tempDir.path,
      userId: 'alice',
    );

    expect((await scoped.getRoomMembers('r1')).dataOrThrow, isNull);

    await scoped.dispose();
    await Hive.close();
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  test('deleteRoomMembers clears just that room', () async {
    await ds.saveRoomMembers('r1', page(const [RoomUser(userId: 'bob')]));
    await ds.saveRoomMembers('r2', page(const [RoomUser(userId: 'zoe')]));

    await ds.deleteRoomMembers('r1');

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
    expect((await ds.getRoomMembers('r2')).dataOrThrow!.items, hasLength(1));
  });

  test('deleteRoom cascades to the roster, so a room recreated under the '
      'same id cannot resurrect dead members', () async {
    await ds.saveRooms([const ChatRoom(id: 'r1', name: 'R1')]);
    await ds.saveRoomMembers('r1', page(const [RoomUser(userId: 'bob')]));

    await ds.deleteRoom('r1');

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
  });

  test('clear() empties the roster box along with the rest', () async {
    await ds.saveRoomMembers('r1', page(const [RoomUser(userId: 'bob')]));

    await ds.clear();

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
  });

  test('clear() also reaches a roster box this session never opened — the '
      'test above writes first, which opens it', () async {
    await ds.saveRoomMembers(
      'r1',
      page(const [
        RoomUser(
          userId: 'bob',
          displayName: 'Bob',
          avatarUrl: 'https://cdn/bob.png',
        ),
      ]),
    );
    await ds.dispose();
    await Hive.close();

    // The scenario the sweep has to survive: the app is killed, and the
    // next launch goes straight to "log out" without opening a single
    // group. Nothing asks for a roster, so the box stays closed and a
    // wipe that only walks OPEN boxes leaves third-party ids, names and
    // avatars legible on disk.
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
    await ds.clear();

    expect((await ds.getRoomMembers('r1')).dataOrThrow, isNull);
  });

  test(
    'clear() reaches the receipts and pins boxes on the same terms',
    () async {
      await ds.saveReceipts('r1', [
        ReadReceipt(
          userId: 'bob',
          lastReadMessageId: 'm1',
          lastReadAt: DateTime.utc(2026),
        ),
      ]);
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
      await ds.clear();

      expect((await ds.getReceipts('r1')).dataOrThrow, isEmpty);
    },
  );

  group('eviction', () {
    late HiveChatDatasource limited;

    setUp(() async {
      await ds.dispose();
      await Hive.close();
      limited = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxRooms: 1,
      );
    });

    tearDown(() async {
      await limited.dispose();
      await Hive.close();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('the roster of an evicted room goes with it', () async {
      await limited.saveRoomMembers(
        'old',
        page(const [RoomUser(userId: 'bob')]),
      );
      await limited.saveUnreads([
        UnreadRoom(
          roomId: 'old',
          unreadMessages: 0,
          lastMessageTime: DateTime.utc(2020),
        ),
        UnreadRoom(
          roomId: 'new',
          unreadMessages: 0,
          lastMessageTime: DateTime.utc(2026),
        ),
      ]);

      await limited.saveRooms([
        const ChatRoom(id: 'old', name: 'Old'),
        const ChatRoom(id: 'new', name: 'New'),
      ]);

      expect((await limited.getRoomMembers('old')).dataOrThrow, isNull);
    });
  });
}
