import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late Directory tempDir;
  final openStores = <HiveChatDatasource>[];

  Future<HiveChatDatasource> open({String? userId, int? maxUsers}) async {
    final ds = await HiveChatDatasource.create(
      basePath: tempDir.path,
      userId: userId,
      maxUsers: maxUsers,
    );
    openStores.add(ds);
    return ds;
  }

  /// Closes the store the way a process exit does, so the next [open] is a
  /// genuine cold start against the same directory on disk.
  Future<void> restart(HiveChatDatasource ds) async {
    openStores.remove(ds);
    await ds.dispose();
    await Hive.close();
  }

  CachedHostUser entry(
    String id, {
    String? name,
    String? avatarUrl,
    bool gone = false,
    DateTime? at,
  }) => CachedHostUser(
    user: HostUser(id: id, displayName: name, avatarUrl: avatarUrl, gone: gone),
    updatedAt: at ?? DateTime.utc(2026, 9, 5, 12),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_host_users_');
  });

  tearDown(() async {
    for (final ds in openStores.toList()) {
      await ds.dispose();
    }
    openStores.clear();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the host directory box', () {
    test('stores a name and gives it back with its timestamp', () async {
      final ds = await open();
      await ds.saveHostUsers([
        entry('bob', name: 'Bob Marsh', avatarUrl: 'https://x/bob.png'),
      ]);

      final read = (await ds.getHostUser('bob')).dataOrNull;
      expect(read, isNotNull);
      expect(read!.user.displayName, 'Bob Marsh');
      expect(read.user.avatarUrl, 'https://x/bob.png');
      expect(read.user.gone, isFalse);
      expect(read.updatedAt, DateTime.utc(2026, 9, 5, 12));
    });

    test('an id nobody stored reads as null, not as an empty entry', () async {
      final ds = await open();
      expect((await ds.getHostUser('nobody')).dataOrNull, isNull);
      expect((await ds.getHostUsers()).dataOrNull, isEmpty);
    });

    test('a name survives a restart of the store', () async {
      final first = await open(userId: 'me');
      await first.saveHostUsers([entry('bob', name: 'Bob Marsh')]);
      await restart(first);

      final second = await open(userId: 'me');
      final read = (await second.getHostUser('bob')).dataOrNull;
      expect(read?.user.displayName, 'Bob Marsh');
    });

    test('an absent person survives as absent, not as unknown', () async {
      final first = await open(userId: 'me');
      await first.saveHostUsers([entry('ghost', gone: true)]);
      await restart(first);

      final second = await open(userId: 'me');
      final read = (await second.getHostUser('ghost')).dataOrNull;
      expect(read, isNotNull, reason: 'a settled "nobody" is an answer');
      expect(read!.user.gone, isTrue);
      expect(read.user.displayName, isNull);
    });

    test('a later answer replaces the earlier one for the same id', () async {
      final ds = await open();
      await ds.saveHostUsers([
        entry('bob', name: 'Bob', at: DateTime.utc(2026, 1, 1)),
      ]);
      await ds.saveHostUsers([
        entry('bob', name: 'Robert', at: DateTime.utc(2026, 9, 1)),
      ]);

      final all = (await ds.getHostUsers()).dataOrNull!;
      expect(all.length, 1);
      expect(all.single.user.displayName, 'Robert');
      expect(all.single.updatedAt, DateTime.utc(2026, 9, 1));
    });

    test('saving nothing is not an error and writes nothing', () async {
      final ds = await open();
      final result = await ds.saveHostUsers(const []);
      expect(result.isSuccess, isTrue);
      expect((await ds.getHostUsers()).dataOrNull, isEmpty);
    });

    test('clearHostUsers empties it and leaves chat profiles alone', () async {
      final ds = await open();
      await ds.saveHostUsers([entry('bob', name: 'Bob Marsh')]);
      await ds.saveUsers([const ChatUser(id: 'bob', displayName: 'bob@chat')]);

      await ds.clearHostUsers();

      expect((await ds.getHostUsers()).dataOrNull, isEmpty);
      final chatProfile = (await ds.getUser('bob')).dataOrNull;
      expect(chatProfile?.displayName, 'bob@chat');
    });

    test('a corrupt row costs one name, not the box', () async {
      final ds = await open();
      await ds.saveHostUsers([
        entry('bob', name: 'Bob Marsh'),
        entry('amy', name: 'Amy Vaz'),
      ]);
      final box = await Hive.openBox<Map<dynamic, dynamic>>(
        HiveChatDatasource.physicalBoxName('chat_host_users'),
      );
      await box.put('broken', {'id': 'broken', 'updatedAt': 'not-a-date'});

      final all = (await ds.getHostUsers()).dataOrNull!;
      expect(all.map((e) => e.user.id).toSet(), {'bob', 'amy'});
      expect((await ds.getHostUser('broken')).dataOrNull, isNull);
    });

    test('the box is bounded by the same ceiling as chat users', () async {
      final ds = await open(maxUsers: 2);
      await ds.saveHostUsers([
        entry('a', name: 'A'),
        entry('b', name: 'B'),
        entry('c', name: 'C'),
      ]);

      final all = (await ds.getHostUsers()).dataOrNull!;
      expect(all.length, 2);
      expect(all.map((e) => e.user.id), isNot(contains('a')));
    });
  });

  group('the host directory box and the rest of the store', () {
    test('adding it does not wipe an existing store on reopen', () async {
      final first = await open(userId: 'me');
      await first.saveRooms([
        const ChatRoom(id: 'room-1', owner: 'me', name: 'Standup'),
      ]);
      await first.saveUsers([const ChatUser(id: 'bob', displayName: 'Bob')]);
      await restart(first);

      // A schema bump would have run the wipe migration here.
      final second = await open(userId: 'me');
      expect((await second.getRooms()).dataOrNull!.single.name, 'Standup');
      expect((await second.getUser('bob')).dataOrNull?.displayName, 'Bob');
    });

    test('one account never reads the other account\'s names', () async {
      final mine = await open(userId: 'me');
      await mine.saveHostUsers([entry('bob', name: 'Bob Marsh')]);
      await restart(mine);

      final theirs = await open(userId: 'someone-else');
      expect((await theirs.getHostUser('bob')).dataOrNull, isNull);
      expect((await theirs.getHostUsers()).dataOrNull, isEmpty);
    });

    test('clear() takes the host names with it', () async {
      final ds = await open(userId: 'me');
      await ds.saveHostUsers([entry('bob', name: 'Bob Marsh')]);

      await ds.clear();

      expect((await ds.getHostUsers()).dataOrNull, isEmpty);
    });

    test('a stored name is not mistaken for a room id', () async {
      // The store harvests room ids out of every global box it does not
      // know to skip; a user id harvested that way would have per-room
      // boxes created and reaped under a person's name.
      final ds = await open(userId: 'me');
      await ds.saveHostUsers([entry('bob', name: 'Bob Marsh')]);
      await ds.saveRooms([const ChatRoom(id: 'room-1', owner: 'me')]);

      await ds.deleteRoom('room-1');
      expect(
        (await ds.getHostUser('bob')).dataOrNull?.user.displayName,
        'Bob Marsh',
      );
    });
  });
}
