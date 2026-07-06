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

  group('corrupted data resilience', () {
    test('getMessages skips corrupted records', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'good',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'ok',
        ),
      ]);
      final box = await Hive.openBox<Map>('chat_messages_room-1');
      await box.put('bad', {'garbage': true});
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'good');
    });

    test('getRooms skips corrupted records', () async {
      await ds.saveRooms([const ChatRoom(id: 'good')]);
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('bad', {'garbage': true});
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.id, 'good');
    });

    test('getRoom returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('corrupted', {'garbage': true});
      final room = (await ds.getRoom('corrupted')).dataOrNull;
      expect(room, isNull);
    });

    test('getUser returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_users');
      await box.put('corrupted', {'garbage': true});
      final user = (await ds.getUser('corrupted')).dataOrNull;
      expect(user, isNull);
    });

    test('getUnreads skips corrupted records', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'good', unreadMessages: 1),
      ]);
      final box = await Hive.openBox<Map>('chat_unreads');
      await box.put('bad', {'garbage': true});
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
    });

    test('getRoomDetail returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_room_details');
      await box.put('corrupted', {'garbage': true});
      final detail = (await ds.getRoomDetail('corrupted')).dataOrNull;
      expect(detail, isNull);
    });

    test('getContacts skips corrupted records', () async {
      await ds.saveContacts([const ChatContact(userId: 'good')]);
      final box = await Hive.openBox<Map>('chat_contacts');
      await box.put(99, {'garbage': true});
      final contacts = (await ds.getContacts()).dataOrNull!;
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'good');
    });

    test('getInvitedRooms skips corrupted records', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'good', invitedBy: 'user-1'),
      ]);
      final box = await Hive.openBox<Map>('chat_invited');
      await box.put(99, {'garbage': true});
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.roomId, 'good');
    });

    test('getRooms warns with a concrete reason per corrupted record and an '
        'aggregated count', () async {
      final warnings = <String>[];
      ds.onWarning = warnings.add;
      await ds.saveRooms([const ChatRoom(id: 'good')]);
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('bad-1', {'garbage': true});
      await box.put('bad-2', {'garbage': true});
      (await ds.getRooms()).dataOrNull;
      final perRecordWarnings = warnings
          .where((w) => w.contains('Discarding corrupted record'))
          .toList();
      expect(perRecordWarnings, hasLength(2));
      expect(perRecordWarnings.first, contains('in rooms'));
      expect(perRecordWarnings.first, matches(RegExp(r':\s+\S')));
      final aggregatedWarnings = warnings
          .where((w) => w.contains('Skipped'))
          .toList();
      expect(aggregatedWarnings, hasLength(1));
      expect(aggregatedWarnings.first, contains('Skipped 2 corrupted records'));
      expect(aggregatedWarnings.first, contains('in rooms'));
    });

    test(
      'getMessages warns with key and error detail per corrupted record',
      () async {
        final warnings = <String>[];
        ds.onWarning = warnings.add;
        await ds.saveMessages('room-1', [
          ChatMessage(
            id: 'good',
            from: 'user-1',
            timestamp: DateTime.utc(2026),
            text: 'ok',
          ),
        ]);
        final box = await Hive.openBox<Map>('chat_messages_room-1');
        await box.put('bad-key', {'garbage': true});
        (await ds.getMessages('room-1')).dataOrNull;
        final corruptionWarnings = warnings
            .where((w) => w.contains('Skipped corrupted message'))
            .toList();
        expect(corruptionWarnings, hasLength(1));
        expect(corruptionWarnings.first, contains('"bad-key"'));
        expect(corruptionWarnings.first, matches(RegExp(r':\s+\S')));
      },
    );
  });

  group('operations on non-existent IDs', () {
    test('updateMessage on non-existent message is a no-op', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'original',
        ),
      ]);
      final ghost = ChatMessage(
        id: 'msg-ghost',
        from: 'user-1',
        timestamp: DateTime.utc(2026),
        text: 'ghost',
      );
      await ds.updateMessage('room-1', ghost);
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'msg-1');
    });

    test('deleteMessage with non-existent ID is a no-op', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'keep',
        ),
      ]);
      await ds.deleteMessage('room-1', 'nonexistent');
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);
    });

    test('deleteRoom with non-existent ID is a no-op', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.deleteRoom('nonexistent');
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
    });

    test('deleteUser with non-existent ID is a no-op', () async {
      await ds.saveUsers([const ChatUser(id: 'user-1')]);
      await ds.deleteUser('nonexistent');
      final users = (await ds.getUsers()).dataOrNull!;
      expect(users.length, 1);
    });
  });

  group('orphaned message boxes', () {
    test('cleans message boxes for rooms that no longer exist', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-keep')]);
      await ds.saveMessages('room-keep', [
        ChatMessage(
          id: 'msg-keep',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'keep',
        ),
      ]);
      await ds.saveMessages('room-orphan', [
        ChatMessage(
          id: 'msg-orphan',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'orphan',
        ),
      ]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

      final orphanMessages = (await ds2.getMessages('room-orphan')).dataOrNull!;
      expect(orphanMessages, isEmpty);

      final keptMessages = (await ds2.getMessages('room-keep')).dataOrNull!;
      expect(keptMessages.length, 1);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('schema versioning', () {
    test('wipes data on downgrade', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Old Room')]);
      await ds.saveUsers([const ChatUser(id: 'user-1', displayName: 'Old')]);
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'old data',
        ),
      ]);

      await ds.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('schemaVersion', {'version': 999});
      await metaBox.close();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

      expect((await ds2.getRooms()).dataOrNull, isEmpty);
      expect((await ds2.getUser('user-1')).dataOrNull, isNull);
      expect((await ds2.getMessages('room-1')).dataOrNull, isEmpty);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('wipes data on upgrade with no migration defined', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Old Room')]);
      await ds.saveUsers([const ChatUser(id: 'user-1', displayName: 'Old')]);

      await ds.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('schemaVersion', {'version': 0});
      await metaBox.close();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

      expect((await ds2.getRooms()).dataOrNull, isEmpty);
      expect((await ds2.getUser('user-1')).dataOrNull, isNull);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('preserves data when schema version matches', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Keep')]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final rooms = (await ds2.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.name, 'Keep');

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('executes incremental migration instead of wiping', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Original')]);

      await ds.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('schemaVersion', {'version': 0});
      await metaBox.close();
      await Hive.close();

      final migrationsRun = <int>[];
      final ds2 = await HiveChatDatasource.create(
        basePath: tempDir.path,
        migrations: {
          1: () async {
            migrationsRun.add(1);
          },
          2: () async {
            migrationsRun.add(2);
          },
        },
      );

      expect(migrationsRun, [1, 2]);
      final rooms = (await ds2.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.name, 'Original');

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('enum serialization roundtrips', () {
    group('MessageType', () {
      for (final type in MessageType.values) {
        test('roundtrips MessageType.${type.name}', () async {
          final msg = ChatMessage(
            id: 'msg-${type.name}',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 1, 1),
            text: 'test',
            messageType: type,
          );
          await ds.saveMessages('room-1', [msg]);
          final loaded = (await ds.getMessages('room-1')).dataOrNull!.first;
          expect(loaded.messageType, type);
        });
      }
    });

    group('ReceiptStatus', () {
      for (final status in ReceiptStatus.values) {
        test('roundtrips ReceiptStatus.${status.name}', () async {
          final msg = ChatMessage(
            id: 'msg-${status.name}',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 1, 1),
            text: 'test',
            receipt: status,
          );
          await ds.saveMessages('room-1', [msg]);
          final loaded = (await ds.getMessages('room-1')).dataOrNull!.first;
          expect(loaded.receipt, status);
        });
      }
    });

    group('RoomAudience', () {
      for (final audience in RoomAudience.values) {
        test('roundtrips RoomAudience.${audience.name}', () async {
          final room = ChatRoom(
            id: 'room-${audience.name}',
            audience: audience,
          );
          await ds.saveRooms([room]);
          final loaded = (await ds.getRoom('room-${audience.name}')).dataOrNull;
          expect(loaded!.audience, audience);
        });
      }
    });

    group('UserRole', () {
      for (final role in UserRole.values) {
        test('roundtrips UserRole.${role.name}', () async {
          final user = ChatUser(id: 'user-${role.name}', role: role);
          await ds.saveUsers([user]);
          final loaded = (await ds.getUser('user-${role.name}')).dataOrNull;
          expect(loaded!.role, role);
        });
      }
    });

    group('RoomRole', () {
      for (final role in RoomRole.values) {
        test('roundtrips RoomRole.${role.name}', () async {
          final detail = RoomDetail(
            id: 'room-${role.name}',
            type: RoomType.group,
            memberCount: 1,
            userRole: role,
            config: const RoomConfig(),
          );
          await ds.saveRoomDetail(detail);
          final loaded = (await ds.getRoomDetail(
            'room-${role.name}',
          )).dataOrNull;
          expect(loaded!.userRole, role);
        });
      }
    });

    group('RoomType', () {
      for (final type in RoomType.values) {
        test('roundtrips RoomType.${type.name}', () async {
          final detail = RoomDetail(
            id: 'room-${type.name}',
            type: type,
            memberCount: 1,
            userRole: RoomRole.member,
            config: const RoomConfig(),
          );
          await ds.saveRoomDetail(detail);
          final loaded = (await ds.getRoomDetail(
            'room-${type.name}',
          )).dataOrNull;
          expect(loaded!.type, type);
        });
      }
    });

    group('WebhookAuthType', () {
      for (final authType in WebhookAuthType.values) {
        test('roundtrips WebhookAuthType.${authType.name}', () async {
          final user = ChatUser(
            id: 'user-${authType.name}',
            configuration: UserConfiguration(
              webhook: WebhookConfig(
                url: 'https://example.com',
                authType: authType,
              ),
            ),
          );
          await ds.saveUsers([user]);
          final loaded = (await ds.getUser('user-${authType.name}')).dataOrNull;
          expect(loaded!.configuration!.webhook!.authType, authType);
        });
      }
    });
  });

  group('field serialization exhaustive', () {
    test('message with null text roundtrips', () async {
      final msg = ChatMessage(
        id: 'msg-null-text',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1),
      );
      await ds.saveMessages('room-1', [msg]);
      final loaded = (await ds.getMessages('room-1')).dataOrNull!.first;
      expect(loaded.text, isNull);
      expect(loaded.id, 'msg-null-text');
    });

    test('message with nested metadata roundtrips', () async {
      final msg = ChatMessage(
        id: 'msg-meta',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1),
        metadata: const {
          'string': 'value',
          'int': 42,
          'bool': true,
          'list': [1, 'two', 3.0],
          'nested': {
            'deep': {'key': 'val'},
          },
          'null_val': null,
        },
      );
      await ds.saveMessages('room-1', [msg]);
      final loaded = (await ds.getMessages('room-1')).dataOrNull!.first;
      expect(loaded.metadata!['string'], 'value');
      expect(loaded.metadata!['int'], 42);
      expect(loaded.metadata!['bool'], true);
      expect(loaded.metadata!['list'], [1, 'two', 3.0]);
      expect((loaded.metadata!['nested'] as Map)['deep'], {'key': 'val'});
    });

    test('message with only required fields roundtrips', () async {
      final msg = ChatMessage(
        id: 'msg-min',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 6, 1),
      );
      await ds.saveMessages('room-1', [msg]);
      final loaded = (await ds.getMessages('room-1')).dataOrNull!.first;
      expect(loaded.id, 'msg-min');
      expect(loaded.from, 'user-1');
      expect(loaded.timestamp, DateTime.utc(2026, 6, 1));
      expect(loaded.text, isNull);
      expect(loaded.messageType, MessageType.regular);
      expect(loaded.attachmentUrl, isNull);
      expect(loaded.referencedMessageId, isNull);
      expect(loaded.reaction, isNull);
      expect(loaded.reply, isNull);
      expect(loaded.metadata, isNull);
      expect(loaded.receipt, isNull);
    });

    test('user with all optional fields roundtrips', () async {
      const user = ChatUser(
        id: 'user-full',
        displayName: 'Full User',
        avatarUrl: 'https://example.com/avatar.png',
        bio: 'A test user with all fields',
        email: 'full@example.com',
        role: UserRole.owner,
        active: false,
        custom: {'theme': 'dark', 'lang': 'es'},
      );
      await ds.saveUsers([user]);
      final loaded = (await ds.getUser('user-full')).dataOrNull;
      expect(loaded!.displayName, 'Full User');
      expect(loaded.avatarUrl, 'https://example.com/avatar.png');
      expect(loaded.bio, 'A test user with all fields');
      expect(loaded.email, 'full@example.com');
      expect(loaded.role, UserRole.owner);
      expect(loaded.active, false);
      expect(loaded.custom, {'theme': 'dark', 'lang': 'es'});
    });

    test('room with all optional fields roundtrips', () async {
      const room = ChatRoom(
        id: 'room-full',
        owner: 'user-1',
        name: 'Full Room',
        subject: 'Testing all fields',
        audience: RoomAudience.contacts,
        allowInvitations: true,
        members: ['user-1', 'user-2'],
        publicToken: 'abc123',
        avatarUrl: 'https://example.com/room.png',
        custom: {'color': 'blue'},
      );
      await ds.saveRooms([room]);
      final loaded = (await ds.getRoom('room-full')).dataOrNull;
      expect(loaded!.owner, 'user-1');
      expect(loaded.name, 'Full Room');
      expect(loaded.subject, 'Testing all fields');
      expect(loaded.audience, RoomAudience.contacts);
      expect(loaded.allowInvitations, true);
      expect(loaded.members, ['user-1', 'user-2']);
      expect(loaded.publicToken, 'abc123');
      expect(loaded.avatarUrl, 'https://example.com/room.png');
      expect(loaded.custom, {'color': 'blue'});
    });

    test('room with all nulls roundtrips', () async {
      const room = ChatRoom(id: 'room-minimal');
      await ds.saveRooms([room]);
      final loaded = (await ds.getRoom('room-minimal')).dataOrNull;
      expect(loaded!.id, 'room-minimal');
      expect(loaded.owner, isNull);
      expect(loaded.name, isNull);
      expect(loaded.subject, isNull);
      expect(loaded.publicToken, isNull);
      expect(loaded.avatarUrl, isNull);
      expect(loaded.custom, isNull);
    });

    test('room detail with custom map roundtrips', () async {
      const detail = RoomDetail(
        id: 'room-custom',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.owner,
        config: RoomConfig(allowInvitations: true),
        custom: {
          'priority': 'high',
          'tags': ['vip', 'active'],
        },
      );
      await ds.saveRoomDetail(detail);
      final loaded = (await ds.getRoomDetail('room-custom')).dataOrNull;
      expect(loaded!.custom!['priority'], 'high');
      expect(loaded.custom!['tags'], ['vip', 'active']);
      expect(loaded.userRole, RoomRole.owner);
    });

    test('room detail with null createdAt roundtrips', () async {
      const detail = RoomDetail(
        id: 'room-no-date',
        type: RoomType.oneToOne,
        memberCount: 2,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      await ds.saveRoomDetail(detail);
      final loaded = (await ds.getRoomDetail('room-no-date')).dataOrNull;
      expect(loaded!.createdAt, isNull);
    });

    test('unread with all optional fields roundtrips', () async {
      await ds.saveUnreads([
        UnreadRoom(
          roomId: 'room-full-unread',
          unreadMessages: 10,
          lastMessage: 'Last msg',
          lastMessageTime: DateTime.utc(2026, 3, 15, 14, 30),
          lastMessageUserId: 'user-1',
          lastMessageId: 'msg-100',
        ),
      ]);
      final loaded = (await ds.getUnreads()).dataOrNull!;
      final u = loaded.first;
      expect(u.roomId, 'room-full-unread');
      expect(u.unreadMessages, 10);
      expect(u.lastMessage, 'Last msg');
      expect(u.lastMessageTime, DateTime.utc(2026, 3, 15, 14, 30));
      expect(u.lastMessageUserId, 'user-1');
      expect(u.lastMessageId, 'msg-100');
    });
  });
}
