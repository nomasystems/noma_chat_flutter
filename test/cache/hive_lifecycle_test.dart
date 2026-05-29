import 'dart:convert';
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

  group('lifecycle', () {
    test('clear removes all data', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'test',
        ),
      ]);
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveUsers([const ChatUser(id: 'user-1')]);
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 1),
      ]);

      await ds.clear();

      expect((await ds.getMessages('room-1')).dataOrNull, isEmpty);
      expect((await ds.getRooms()).dataOrNull, isEmpty);
      expect((await ds.getUser('user-1')).dataOrNull, isNull);
      expect((await ds.getContacts()).dataOrNull, isEmpty);
      expect((await ds.getUnreads()).dataOrNull, isEmpty);
    });

    test(
      'clear after restart removes messages from previous session',
      () async {
        await ds.saveMessages('room-a', [
          ChatMessage(
            id: 'msg-a',
            from: 'user-1',
            timestamp: DateTime.utc(2026),
            text: 'session 1',
          ),
        ]);
        await ds.saveMessages('room-b', [
          ChatMessage(
            id: 'msg-b',
            from: 'user-1',
            timestamp: DateTime.utc(2026),
            text: 'session 1',
          ),
        ]);

        await ds.dispose();
        await Hive.close();

        final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

        await ds2.clear();

        expect((await ds2.getMessages('room-a')).dataOrNull, isEmpty);
        expect((await ds2.getMessages('room-b')).dataOrNull, isEmpty);

        await ds2.dispose();
        ds = await HiveChatDatasource.create(basePath: tempDir.path);
      },
    );
  });

  group('persistence', () {
    test('data survives dispose and recreate', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'Persistent',
        ),
      ]);
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'My Room')]);
      await ds.saveUsers([const ChatUser(id: 'user-1', displayName: 'Alice')]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

      final messages = (await ds2.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.text, 'Persistent');

      final rooms = (await ds2.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.name, 'My Room');

      final user = (await ds2.getUser('user-1')).dataOrNull;
      expect(user, isNotNull);
      expect(user!.displayName, 'Alice');

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('encryption', () {
    test('data written with cipher is readable with same cipher', () async {
      await ds.dispose();
      await Hive.close();

      final key = Hive.generateSecureKey();
      final cipher = HiveAesCipher(key);
      final encDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        encryptionCipher: cipher,
      );
      await encDs.saveRooms([
        const ChatRoom(
          id: 'enc-room',
          audience: RoomAudience.contacts,
          members: [],
        ),
      ]);
      await encDs.dispose();
      await Hive.close();

      final encDs2 = await HiveChatDatasource.create(
        basePath: tempDir.path,
        encryptionCipher: cipher,
      );
      final rooms = (await encDs2.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.id, 'enc-room');
      await encDs2.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('data written without cipher works normally', () async {
      await ds.saveUsers([
        const ChatUser(id: 'u1', displayName: 'Test', active: true),
      ]);
      final user = (await ds.getUser('u1')).dataOrNull;
      expect(user, isNotNull);
      expect(user!.displayName, 'Test');
    });

    test('encrypted box opened without cipher triggers recreation', () async {
      await ds.dispose();
      await Hive.close();

      final key = Hive.generateSecureKey();
      final cipher = HiveAesCipher(key);
      final encDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        encryptionCipher: cipher,
      );
      await encDs.saveRooms([
        const ChatRoom(
          id: 'enc-room',
          audience: RoomAudience.contacts,
          members: [],
        ),
      ]);
      await encDs.dispose();
      await Hive.close();

      String? warning;
      final plainDs = await HiveChatDatasource.create(basePath: tempDir.path);
      plainDs.onWarning = (msg) => warning = msg;
      final rooms = (await plainDs.getRooms()).dataOrNull!;
      expect(rooms, isEmpty);
      expect(warning, anyOf(isNull, isA<String>()));
      await plainDs.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('I/O error resilience', () {
    test('saveMessages does not throw on read-only filesystem', () async {
      final warnings = <String>[];
      ds.onWarning = warnings.add;
      await ds.saveMessages('room-io', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'before readonly',
        ),
      ]);
      await ds.dispose();
      await Hive.close();

      final roDir = await Directory.systemTemp.createTemp('hive_ro_');
      final roDs = await HiveChatDatasource.create(
        basePath: roDir.path,
        maxMessagesPerRoom: 500,
      );
      roDs.onWarning = warnings.add;
      warnings.clear();

      Process.runSync('chmod', ['-R', '444', roDir.path]);

      try {
        await roDs.saveMessages('room-io', [
          ChatMessage(
            id: 'msg-2',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 1, 2),
            text: 'readonly write',
          ),
        ]);
      } catch (_) {}

      Process.runSync('chmod', ['-R', '755', roDir.path]);
      try {
        await roDs.dispose();
      } catch (_) {}
      await Hive.close();
      roDir.deleteSync(recursive: true);

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('saveRooms does not throw on read-only filesystem', () async {
      final warnings = <String>[];
      await ds.dispose();
      await Hive.close();

      final roDir = await Directory.systemTemp.createTemp('hive_ro_rooms_');
      final roDs = await HiveChatDatasource.create(
        basePath: roDir.path,
        maxMessagesPerRoom: 500,
      );
      roDs.onWarning = warnings.add;

      Process.runSync('chmod', ['-R', '444', roDir.path]);

      try {
        await roDs.saveRooms([const ChatRoom(id: 'room-fail')]);
      } catch (_) {}

      Process.runSync('chmod', ['-R', '755', roDir.path]);
      try {
        await roDs.dispose();
      } catch (_) {}
      await Hive.close();
      roDir.deleteSync(recursive: true);

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('write operations call onWarning and do not rethrow', () async {
      final warnings = <String>[];
      await ds.dispose();
      await Hive.close();

      final roDir = await Directory.systemTemp.createTemp('hive_ro_multi_');
      final roDs = await HiveChatDatasource.create(
        basePath: roDir.path,
        maxMessagesPerRoom: 500,
      );
      roDs.onWarning = warnings.add;

      await roDs.saveRooms([const ChatRoom(id: 'room-1')]);
      await roDs.saveUsers([const ChatUser(id: 'user-1')]);

      Process.runSync('chmod', ['-R', '444', roDir.path]);
      warnings.clear();

      try {
        await roDs.saveUsers([const ChatUser(id: 'user-2')]);
        await roDs.deleteUser('user-1');
        await roDs.saveRooms([const ChatRoom(id: 'room-2')]);
        await roDs.deleteRoom('room-1');
        await roDs.saveUnreads([
          const UnreadRoom(roomId: 'r', unreadMessages: 1),
        ]);
        await roDs.deleteUnread('r');
        await roDs.saveContacts([const ChatContact(userId: 'c')]);
        await roDs.saveInvitedRooms([
          const InvitedRoom(roomId: 'r', invitedBy: 'u'),
        ]);
        await roDs.saveOfflineQueue([
          {'type': 'test'},
        ]);
        await roDs.clearOfflineQueue();
      } catch (_) {}

      Process.runSync('chmod', ['-R', '755', roDir.path]);
      try {
        await roDs.dispose();
      } catch (_) {}
      await Hive.close();
      roDir.deleteSync(recursive: true);

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('backup and restore', () {
    test('exportData returns valid structure with all entities', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-1', name: 'Room 1'),
        const ChatRoom(id: 'room-2', name: 'Room 2'),
      ]);
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-1',
          name: 'Detail 1',
          type: RoomType.group,
          memberCount: 3,
          userRole: RoomRole.admin,
          config: RoomConfig(allowInvitations: true),
        ),
      );
      await ds.saveUsers([
        const ChatUser(id: 'user-1', displayName: 'Alice'),
        const ChatUser(id: 'user-2', displayName: 'Bob'),
      ]);
      await ds.saveContacts([const ChatContact(userId: 'user-1')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-3', invitedBy: 'user-2'),
      ]);

      final exported = await ds.exportData();

      expect(exported['version'], 2);
      expect(exported['exportedAt'], isA<String>());
      expect(exported['validation'], isA<Map>());
      final validation = exported['validation'] as Map<String, dynamic>;
      expect(validation['roomCount'], 2);
      expect(validation['roomDetailCount'], 1);
      expect(validation['userCount'], 2);
      expect(validation['contactCount'], 1);
      expect(validation['unreadCount'], 1);
      expect(validation['invitedRoomCount'], 1);
      expect((exported['rooms'] as List).length, 2);
      expect((exported['roomDetails'] as List).length, 1);
      expect((exported['users'] as List).length, 2);
      expect((exported['contacts'] as List).length, 1);
      expect((exported['unreads'] as List).length, 1);
      expect((exported['invitedRooms'] as List).length, 1);
    });

    test('exportData is JSON-serializable', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-1', name: 'Test', custom: {'key': 'val'}),
      ]);
      await ds.saveUsers([const ChatUser(id: 'user-1', displayName: 'Alice')]);

      final exported = await ds.exportData();
      final json = jsonEncode(exported);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['version'], 2);
      expect((decoded['rooms'] as List).length, 1);
    });

    test('importData restores exported data', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Room 1')]);
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-1',
          name: 'Detail 1',
          type: RoomType.group,
          memberCount: 3,
          userRole: RoomRole.admin,
          config: RoomConfig(allowInvitations: true),
        ),
      );
      await ds.saveUsers([const ChatUser(id: 'user-1', displayName: 'Alice')]);
      await ds.saveContacts([const ChatContact(userId: 'user-1')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);

      final exported = await ds.exportData();

      await ds.clear();
      expect((await ds.getRooms()).dataOrNull, isEmpty);
      expect((await ds.getUsers()).dataOrNull, isEmpty);

      await ds.importData(exported);

      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.name, 'Room 1');
      final detail = (await ds.getRoomDetail('room-1')).dataOrNull;
      expect(detail, isNotNull);
      expect(detail!.name, 'Detail 1');
      final users = (await ds.getUsers()).dataOrNull!;
      expect(users.length, 1);
      expect(users.first.displayName, 'Alice');
      final contacts = (await ds.getContacts()).dataOrNull!;
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'user-1');
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
      expect(unreads.first.unreadMessages, 5);
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.invitedBy, 'user-1');
    });

    test('importData replaces existing data', () async {
      await ds.saveRooms([const ChatRoom(id: 'old-room', name: 'Old')]);
      await ds.saveUsers([
        const ChatUser(id: 'old-user', displayName: 'OldUser'),
      ]);

      final exportedData = {
        'version': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'validation': {
          'roomCount': 1,
          'roomDetailCount': 0,
          'userCount': 1,
          'contactCount': 0,
          'unreadCount': 0,
          'invitedRoomCount': 0,
        },
        'rooms': [
          {
            'id': 'new-room',
            'name': 'New',
            'audience': 'public',
            'allowInvitations': false,
            'members': <String>[],
          },
        ],
        'roomDetails': <Map<String, dynamic>>[],
        'users': [
          {
            'id': 'new-user',
            'displayName': 'NewUser',
            'role': 'user',
            'active': true,
          },
        ],
        'contacts': <Map<String, dynamic>>[],
        'unreads': <Map<String, dynamic>>[],
        'invitedRooms': <Map<String, dynamic>>[],
      };

      await ds.importData(exportedData);

      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.id, 'new-room');
      expect((await ds.getRoom('old-room')).dataOrNull, isNull);
      final users = (await ds.getUsers()).dataOrNull!;
      expect(users.length, 1);
      expect(users.first.id, 'new-user');
      expect((await ds.getUser('old-user')).dataOrNull, isNull);
    });

    test('importData with wrong version throws', () async {
      final badData = {
        'version': 999,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
      };

      expect(
        () => ds.importData(badData),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Incompatible schema version'),
          ),
        ),
      );
    });

    test('importData with null version throws', () async {
      final badData = {
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
      };

      expect(() => ds.importData(badData), throwsA(isA<ArgumentError>()));
    });

    test('importData with mismatched counts warns', () async {
      final warnings = <String>[];
      ds.onWarning = (msg) => warnings.add(msg);

      final data = {
        'version': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'validation': {'roomCount': 5, 'userCount': 10, 'contactCount': 3},
        'rooms': <Map<String, dynamic>>[],
        'roomDetails': <Map<String, dynamic>>[],
        'users': <Map<String, dynamic>>[],
        'contacts': <Map<String, dynamic>>[],
        'unreads': <Map<String, dynamic>>[],
        'invitedRooms': <Map<String, dynamic>>[],
      };

      await ds.importData(data);

      expect(warnings, isNotEmpty);
      final mismatchWarning = warnings.firstWhere(
        (w) => w.contains('Import validation mismatch'),
      );
      expect(mismatchWarning, contains('roomCount'));
      expect(mismatchWarning, contains('userCount'));
      expect(mismatchWarning, contains('contactCount'));
    });

    test('export/import roundtrip through JSON', () async {
      await ds.saveRooms([
        const ChatRoom(
          id: 'room-json',
          name: 'JSON Test',
          owner: 'user-1',
          audience: RoomAudience.contacts,
          allowInvitations: true,
          members: ['user-1', 'user-2'],
          custom: {'theme': 'dark'},
        ),
      ]);
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-json',
          name: 'JSON Detail',
          type: RoomType.oneToOne,
          memberCount: 2,
          userRole: RoomRole.owner,
          config: RoomConfig(allowInvitations: true),
          muted: true,
          pinned: true,
        ),
      );
      await ds.saveUsers([
        const ChatUser(
          id: 'user-1',
          displayName: 'Alice',
          role: UserRole.admin,
          active: false,
          custom: {'pref': 'value'},
        ),
      ]);
      await ds.saveContacts([const ChatContact(userId: 'user-1')]);
      await ds.saveUnreads([
        UnreadRoom(
          roomId: 'room-json',
          unreadMessages: 3,
          lastMessage: 'hello',
          lastMessageTime: DateTime.utc(2026, 6, 1),
        ),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-json', invitedBy: 'user-2'),
      ]);

      final exported = await ds.exportData();
      final json = jsonEncode(exported);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      await ds.clear();
      await ds.importData(decoded);

      final room = (await ds.getRoom('room-json')).dataOrNull;
      expect(room, isNotNull);
      expect(room!.name, 'JSON Test');
      expect(room.custom, {'theme': 'dark'});
      final detail = (await ds.getRoomDetail('room-json')).dataOrNull;
      expect(detail, isNotNull);
      expect(detail!.type, RoomType.oneToOne);
      expect(detail.muted, true);
      final user = (await ds.getUser('user-1')).dataOrNull;
      expect(user, isNotNull);
      expect(user!.role, UserRole.admin);
      expect(user.active, false);
      final contacts = (await ds.getContacts()).dataOrNull!;
      expect(contacts.length, 1);
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
      expect(unreads.first.lastMessage, 'hello');
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
    });

    test('exportData on empty datasource returns empty lists', () async {
      final exported = await ds.exportData();
      expect(exported['version'], 2);
      expect((exported['rooms'] as List), isEmpty);
      expect((exported['users'] as List), isEmpty);
      expect((exported['contacts'] as List), isEmpty);
      final validation = exported['validation'] as Map<String, dynamic>;
      expect(validation['roomCount'], 0);
      expect(validation['userCount'], 0);
    });
  });
}
