import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// Round-trip coverage for the `custom`/`metadata` free-form maps of
/// [UnreadRoom], [ChatRoom], [ChatUser] and [RoomDetail] against the real
/// Hive datasource (not the in-memory fake), so a value that only survives
/// a shallow `Map<dynamic, dynamic>` -> `Map<String, dynamic>` cast
/// in-process but not an actual disk encode/decode would be caught. Hive
/// always decodes nested maps/lists as `Map<dynamic, dynamic>`/`List<dynamic>`
/// regardless of what was written, so a nested value only comes back
/// correctly typed when the outer cast is applied recursively.
void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_unread_custom_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UnreadRoom.custom round-trip through real Hive storage', () {
    test('a nested custom map survives a simulated app restart', () async {
      const custom = {
        'support': true,
        'meta': {'k': 1},
      };
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 3, custom: custom),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final unreads = (await ds2.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);

      final back = unreads.first.custom;
      expect(back, custom);
      expect(back, isA<Map<String, dynamic>>());
      expect(back!['meta'], isA<Map<String, dynamic>>());

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('a null custom survives a simulated app restart', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-2', unreadMessages: 1),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final unreads = (await ds2.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
      expect(unreads.first.custom, isNull);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test(
      'a row persisted before the field existed reads back with custom null',
      () async {
        final box = await Hive.openBox<Map>('chat_unreads');
        await box.put('room-legacy', {
          'roomId': 'room-legacy',
          'unreadMessages': 2,
        });

        final unreads = (await ds.getUnreads()).dataOrNull!;
        final legacy = unreads.firstWhere((u) => u.roomId == 'room-legacy');
        expect(legacy.custom, isNull);
      },
    );
  });

  group('ChatRoom.custom round-trip through real Hive storage', () {
    test('a custom map with a nested map and a nested list survives a '
        'simulated app restart', () async {
      const custom = {
        'tags': ['a', 'b'],
        'meta': {'k': 1},
      };
      await ds.saveRooms([
        const ChatRoom(id: 'room-1', name: 'Room 1', custom: custom),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final room = (await ds2.getRoom('room-1')).dataOrNull!;

      final back = room.custom;
      expect(back, custom);
      expect(back, isA<Map<String, dynamic>>());
      expect(back!['meta'], isA<Map<String, dynamic>>());
      expect(back['tags'], isA<List<dynamic>>());

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('ChatUser.custom round-trip through real Hive storage', () {
    test('a custom map with a nested map and a nested list survives a '
        'simulated app restart', () async {
      const custom = {
        'tags': ['vip', 'beta'],
        'meta': {'k': 2},
      };
      await ds.saveUsers([
        const ChatUser(id: 'user-1', displayName: 'Alice', custom: custom),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final user = (await ds2.getUser('user-1')).dataOrNull!;

      final back = user.custom;
      expect(back, custom);
      expect(back, isA<Map<String, dynamic>>());
      expect(back!['meta'], isA<Map<String, dynamic>>());
      expect(back['tags'], isA<List<dynamic>>());

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('RoomDetail.custom round-trip through real Hive storage', () {
    test('a custom map with a nested map and a nested list survives a '
        'simulated app restart', () async {
      const custom = {
        'tags': ['pinned', 'important'],
        'meta': {'k': 3},
      };
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-detail-1',
          type: RoomType.group,
          memberCount: 2,
          userRole: RoomRole.member,
          config: RoomConfig(),
          custom: custom,
        ),
      );

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final detail = (await ds2.getRoomDetail('room-detail-1')).dataOrNull!;

      final back = detail.custom;
      expect(back, custom);
      expect(back, isA<Map<String, dynamic>>());
      expect(back!['meta'], isA<Map<String, dynamic>>());
      expect(back['tags'], isA<List<dynamic>>());

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('ChatMessage.metadata round-trip through real Hive storage', () {
    test('a metadata map with a nested map and a nested list survives a '
        'simulated app restart', () async {
      const metadata = {
        'reactions': ['👍', '❤️'],
        'edit': {'v': 2},
      };
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'hi',
          metadata: metadata,
        ),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final messages = (await ds2.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);

      final back = messages.first.metadata;
      expect(back, metadata);
      expect(back, isA<Map<String, dynamic>>());
      expect(back!['edit'], isA<Map<String, dynamic>>());
      expect(back['reactions'], isA<List<dynamic>>());

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });
}
