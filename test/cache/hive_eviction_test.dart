import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('eviction edge cases', () {
    late HiveChatDatasource limitedDs;

    setUp(() async {
      await ds.dispose();
      await Hive.close();
      limitedDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxMessagesPerRoom: 5,
      );
    });

    tearDown(() async {
      await limitedDs.dispose();
      await Hive.close();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('exactly at limit does not evict', () async {
      final messages = List.generate(
        5,
        (i) => ChatMessage(
          id: 'msg-$i',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
          text: 'Message $i',
        ),
      );
      await limitedDs.saveMessages('room-1', messages);
      final stored = (await limitedDs.getMessages('room-1')).dataOrNull!;
      expect(stored.length, 5);
    });

    test('one over limit evicts the oldest', () async {
      final messages = List.generate(
        6,
        (i) => ChatMessage(
          id: 'msg-$i',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
          text: 'Message $i',
        ),
      );
      await limitedDs.saveMessages('room-1', messages);
      final stored = (await limitedDs.getMessages('room-1')).dataOrNull!;
      expect(stored.length, 5);
      expect(stored.last.id, 'msg-1');
      expect(stored.first.id, 'msg-5');
    });

    test('incremental saves that exceed limit trigger eviction', () async {
      final batch1 = List.generate(
        3,
        (i) => ChatMessage(
          id: 'msg-$i',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
          text: 'Batch1 $i',
        ),
      );
      await limitedDs.saveMessages('room-1', batch1);

      final batch2 = List.generate(
        4,
        (i) => ChatMessage(
          id: 'msg-${i + 3}',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i + 3),
          text: 'Batch2 $i',
        ),
      );
      await limitedDs.saveMessages('room-1', batch2);

      final stored = (await limitedDs.getMessages('room-1')).dataOrNull!;
      expect(stored.length, 5);
      expect(stored.first.id, 'msg-6');
      expect(stored.last.id, 'msg-2');
    });

    test('maxMessagesPerRoom=1 retains only the newest', () async {
      await limitedDs.dispose();
      await Hive.close();
      final ds1 = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxMessagesPerRoom: 1,
      );

      await ds1.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-old',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'old',
        ),
        ChatMessage(
          id: 'msg-new',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 2),
          text: 'new',
        ),
      ]);
      final stored = (await ds1.getMessages('room-1')).dataOrNull!;
      expect(stored.length, 1);
      expect(stored.first.id, 'msg-new');

      await ds1.dispose();
      await Hive.close();
      limitedDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxMessagesPerRoom: 5,
      );
    });
  });

  group('eviction with timestamp-sorted keys', () {
    test('eviction removes oldest keys first', () async {
      await ds.dispose();
      await Hive.close();
      final limitedDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxMessagesPerRoom: 2,
      );

      await limitedDs.saveMessages('room-ts', [
        ChatMessage(
          id: 'msg-old',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'old',
        ),
        ChatMessage(
          id: 'msg-mid',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 6, 1),
          text: 'mid',
        ),
        ChatMessage(
          id: 'msg-new',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 12, 1),
          text: 'new',
        ),
      ]);

      final stored = (await limitedDs.getMessages('room-ts')).dataOrNull!;
      expect(stored.length, 2);
      final ids = stored.map((m) => m.id).toSet();
      expect(ids.contains('msg-old'), isFalse);
      expect(ids.contains('msg-mid'), isTrue);
      expect(ids.contains('msg-new'), isTrue);

      await limitedDs.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test(
      'entries with non-timestamp keys are evicted first (sorted before ISO dates)',
      () async {
        await ds.dispose();
        await Hive.close();
        final limitedDs = await HiveChatDatasource.create(
          basePath: tempDir.path,
          maxMessagesPerRoom: 2,
        );

        await limitedDs.saveMessages('room-bad-ts', [
          ChatMessage(
            id: 'msg-good-1',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 6, 1),
            text: 'good 1',
          ),
          ChatMessage(
            id: 'msg-good-2',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 6, 2),
            text: 'good 2',
          ),
        ]);

        final stored = (await limitedDs.getMessages('room-bad-ts')).dataOrNull!;
        expect(stored.length, 2);
        expect(stored.first.id, 'msg-good-2');
        expect(stored.last.id, 'msg-good-1');

        await limitedDs.dispose();
        ds = await HiveChatDatasource.create(basePath: tempDir.path);
      },
    );
  });

  group('entity eviction limits', () {
    test('rooms are evicted when exceeding maxRooms', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path, maxRooms: 2);
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 2);
      final ids = rooms.map((r) => r.id).toSet();
      expect(ids.contains('r3'), isTrue);
      expect(ids.contains('r2'), isTrue);
    });

    test('users are evicted when exceeding maxUsers', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path, maxUsers: 2);
      await ds.saveUsers([
        const ChatUser(id: 'u1', displayName: 'A', active: true),
        const ChatUser(id: 'u2', displayName: 'B', active: true),
        const ChatUser(id: 'u3', displayName: 'C', active: true),
      ]);
      final users = (await ds.getUsers()).dataOrNull!;
      expect(users.length, 2);
    });

    test('no limit means no eviction', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 3);
    });

    test('at limit does not evict', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path, maxRooms: 3);
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 3);
    });
  });
}
