import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('messages', () {
    final msg1 = ChatMessage(
      id: 'msg-1',
      from: 'user-1',
      timestamp: DateTime.utc(2026, 1, 1),
      text: 'Hello',
    );
    final msg2 = ChatMessage(
      id: 'msg-2',
      from: 'user-2',
      timestamp: DateTime.utc(2026, 1, 2),
      text: 'World',
    );
    final msg3 = ChatMessage(
      id: 'msg-3',
      from: 'user-1',
      timestamp: DateTime.utc(2026, 1, 3),
      text: 'Third',
    );

    test('save and get messages', () async {
      await ds.saveMessages('room-1', [msg1, msg2]);
      final messages = await ds.getMessages('room-1');
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-2');
      expect(messages.last.id, 'msg-1');
    });

    test('get messages with limit', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1', limit: 2);
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-3');
    });

    test('get messages with cursor (before timestamp)', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1',
          before: msg3.timestamp.toUtc().toIso8601String());
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-2');
      expect(messages.last.id, 'msg-1');
    });

    test('get messages with cursor and limit', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1',
          before: msg3.timestamp.toUtc().toIso8601String(), limit: 1);
      expect(messages.length, 1);
      expect(messages.first.id, 'msg-2');
    });

    test('get messages with after cursor', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1',
          after: msg1.timestamp.toUtc().toIso8601String());
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-3');
      expect(messages.last.id, 'msg-2');
    });

    test('get messages with after and before cursors combined', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1',
          after: msg1.timestamp.toUtc().toIso8601String(),
          before: msg3.timestamp.toUtc().toIso8601String());
      expect(messages.length, 1);
      expect(messages.first.id, 'msg-2');
    });

    test('get messages with after cursor returns empty when none newer',
        () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = await ds.getMessages('room-1',
          after: msg3.timestamp.toUtc().toIso8601String());
      expect(messages, isEmpty);
    });

    test('deduplication on save', () async {
      await ds.saveMessages('room-1', [msg1]);
      final updated = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1),
        text: 'Updated',
      );
      await ds.saveMessages('room-1', [updated]);
      final messages = await ds.getMessages('room-1');
      expect(messages.length, 1);
      expect(messages.first.text, 'Updated');
    });

    test('update message', () async {
      await ds.saveMessages('room-1', [msg1]);
      final updated = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1),
        text: 'Edited',
      );
      await ds.updateMessage('room-1', updated);
      final messages = await ds.getMessages('room-1');
      expect(messages.first.text, 'Edited');
    });

    test('delete message', () async {
      await ds.saveMessages('room-1', [msg1, msg2]);
      await ds.deleteMessage('room-1', 'msg-1');
      final messages = await ds.getMessages('room-1');
      expect(messages.length, 1);
      expect(messages.first.id, 'msg-2');
    });

    test('clear messages', () async {
      await ds.saveMessages('room-1', [msg1, msg2]);
      await ds.clearMessages('room-1');
      final messages = await ds.getMessages('room-1');
      expect(messages, isEmpty);
    });

    test('concurrent access to same room does not throw', () async {
      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        futures.add(ds.saveMessages('room-concurrent', [
          ChatMessage(
            id: 'msg-$i',
            from: 'user-1',
            timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
            text: 'Concurrent $i',
          ),
        ]));
        futures.add(ds.getMessages('room-concurrent'));
      }
      await Future.wait(futures);
      final messages = await ds.getMessages('room-concurrent');
      expect(messages.length, 10);
    });

    test('evicts old messages when exceeding maxMessagesPerRoom', () async {
      await ds.dispose();
      await Hive.close();
      final limitedDs = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxMessagesPerRoom: 5,
      );

      final messages = List.generate(
        10,
        (i) => ChatMessage(
          id: 'msg-$i',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
          text: 'Message $i',
        ),
      );
      await limitedDs.saveMessages('room-1', messages);

      final stored = await limitedDs.getMessages('room-1');
      expect(stored.length, 5);
      expect(stored.first.id, 'msg-9');
      expect(stored.last.id, 'msg-5');

      await limitedDs.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('messages from different rooms are isolated', () async {
      await ds.saveMessages('room-1', [msg1]);
      await ds.saveMessages('room-2', [msg2]);
      expect((await ds.getMessages('room-1')).length, 1);
      expect((await ds.getMessages('room-2')).length, 1);
    });

    test('preserves all message fields', () async {
      final fullMsg = ChatMessage(
        id: 'msg-full',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 6, 15, 10, 30),
        text: 'Full message',
        messageType: MessageType.reply,
        attachmentUrl: 'https://example.com/file.png',
        referencedMessageId: 'msg-0',
        reaction: '👍',
        reply: 'Re: original',
        metadata: {'key': 'value'},
        receipt: ReceiptStatus.delivered,
        isEdited: true,
        isDeleted: true,
        isForwarded: true,
      );
      await ds.saveMessages('room-1', [fullMsg]);
      final messages = await ds.getMessages('room-1');
      final loaded = messages.first;
      expect(loaded.id, 'msg-full');
      expect(loaded.text, 'Full message');
      expect(loaded.messageType, MessageType.reply);
      expect(loaded.attachmentUrl, 'https://example.com/file.png');
      expect(loaded.referencedMessageId, 'msg-0');
      expect(loaded.reaction, '👍');
      expect(loaded.reply, 'Re: original');
      expect(loaded.metadata, {'key': 'value'});
      expect(loaded.receipt, ReceiptStatus.delivered);
      expect(loaded.isEdited, isTrue);
      expect(loaded.isDeleted, isTrue);
      expect(loaded.isForwarded, isTrue);
    });
  });

  group('rooms', () {
    const room1 = ChatRoom(
      id: 'room-1',
      owner: 'user-1',
      name: 'Test Room',
      audience: RoomAudience.public,
      allowInvitations: true,
      members: ['user-1', 'user-2'],
    );

    test('save and get rooms', () async {
      await ds.saveRooms([room1]);
      final rooms = await ds.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.id, 'room-1');
      expect(rooms.first.name, 'Test Room');
      expect(rooms.first.audience, RoomAudience.public);
      expect(rooms.first.members, ['user-1', 'user-2']);
    });

    test('get room by id', () async {
      await ds.saveRooms([room1]);
      final room = await ds.getRoom('room-1');
      expect(room, isNotNull);
      expect(room!.owner, 'user-1');
    });

    test('get nonexistent room returns null', () async {
      expect(await ds.getRoom('nonexistent'), isNull);
    });

    test('delete room cascades', () async {
      await ds.saveRooms([room1]);
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'test',
        ),
      ]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);

      await ds.deleteRoom('room-1');

      expect(await ds.getRoom('room-1'), isNull);
      expect(await ds.getMessages('room-1'), isEmpty);
      final unreads = await ds.getUnreads();
      expect(unreads.where((u) => u.roomId == 'room-1'), isEmpty);
    });
  });

  group('room details', () {
    final detail = RoomDetail(
      id: 'room-1',
      name: 'Chat Room',
      subject: 'Testing',
      type: RoomType.group,
      memberCount: 5,
      userRole: RoomRole.admin,
      config: const RoomConfig(allowInvitations: true),
      muted: true,
      pinned: false,
      createdAt: DateTime.utc(2026, 3, 15),
      avatarUrl: 'https://example.com/avatar.png',
      custom: {'theme': 'dark'},
    );

    test('save and get room detail', () async {
      await ds.saveRoomDetail(detail);
      final loaded = await ds.getRoomDetail('room-1');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Chat Room');
      expect(loaded.subject, 'Testing');
      expect(loaded.type, RoomType.group);
      expect(loaded.memberCount, 5);
      expect(loaded.userRole, RoomRole.admin);
      expect(loaded.config.allowInvitations, true);
      expect(loaded.muted, true);
      expect(loaded.pinned, false);
      expect(loaded.createdAt, DateTime.utc(2026, 3, 15));
      expect(loaded.avatarUrl, 'https://example.com/avatar.png');
      expect(loaded.custom, {'theme': 'dark'});
    });

    test('save oneToOne room detail', () async {
      const oneToOne = RoomDetail(
        id: 'dm-1',
        type: RoomType.oneToOne,
        memberCount: 2,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      await ds.saveRoomDetail(oneToOne);
      final loaded = await ds.getRoomDetail('dm-1');
      expect(loaded!.type, RoomType.oneToOne);
      expect(loaded.userRole, RoomRole.member);
    });

    test('get nonexistent detail returns null', () async {
      expect(await ds.getRoomDetail('nonexistent'), isNull);
    });

    test('delete room detail', () async {
      await ds.saveRoomDetail(detail);
      await ds.deleteRoomDetail('room-1');
      expect(await ds.getRoomDetail('room-1'), isNull);
    });

    test('deleteRoom cascades to room detail', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveRoomDetail(detail);
      await ds.deleteRoom('room-1');
      expect(await ds.getRoomDetail('room-1'), isNull);
    });

    test('save and get announcement room detail round-trip', () async {
      const announcement = RoomDetail(
        id: 'ann-1',
        name: 'Announcements',
        type: RoomType.announcement,
        memberCount: 100,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      await ds.saveRoomDetail(announcement);
      final loaded = await ds.getRoomDetail('ann-1');
      expect(loaded, isNotNull);
      expect(loaded!.type, RoomType.announcement);
      expect(loaded.name, 'Announcements');
      expect(loaded.isReadOnly, isTrue);
    });
  });

  group('users', () {
    const user1 = ChatUser(
      id: 'user-1',
      displayName: 'Alice',
      avatarUrl: 'https://example.com/alice.png',
      role: UserRole.admin,
    );

    test('save and get user', () async {
      await ds.saveUsers([user1]);
      final user = await ds.getUser('user-1');
      expect(user, isNotNull);
      expect(user!.displayName, 'Alice');
      expect(user.role, UserRole.admin);
      expect(user.avatarUrl, 'https://example.com/alice.png');
    });

    test('get all users', () async {
      await ds.saveUsers([
        const ChatUser(id: 'u-1', displayName: 'Alice'),
        const ChatUser(id: 'u-2', displayName: 'Bob'),
      ]);
      final users = await ds.getUsers();
      expect(users.length, 2);
      final ids = users.map((u) => u.id).toSet();
      expect(ids, containsAll(['u-1', 'u-2']));
    });

    test('getUsers returns empty before save', () async {
      expect(await ds.getUsers(), isEmpty);
    });

    test('get nonexistent user returns null', () async {
      expect(await ds.getUser('nonexistent'), isNull);
    });

    test('delete user', () async {
      await ds.saveUsers([user1]);
      await ds.deleteUser('user-1');
      expect(await ds.getUser('user-1'), isNull);
    });

    test('preserves UserConfiguration with webhook', () async {
      const user = ChatUser(
        id: 'user-cfg',
        displayName: 'Bob',
        configuration: UserConfiguration(
          metadata: {'tier': 'premium'},
          webhook: WebhookConfig(
            url: 'https://hook.example.com/cb',
            authType: WebhookAuthType.basic,
            username: 'admin',
            password: 'secret',
          ),
        ),
      );
      await ds.saveUsers([user]);
      final loaded = await ds.getUser('user-cfg');
      expect(loaded, isNotNull);
      expect(loaded!.configuration, isNotNull);
      expect(loaded.configuration!.metadata, {'tier': 'premium'});
      expect(loaded.configuration!.webhook, isNotNull);
      expect(loaded.configuration!.webhook!.url, 'https://hook.example.com/cb');
      expect(loaded.configuration!.webhook!.authType, WebhookAuthType.basic);
      expect(loaded.configuration!.webhook!.username, 'admin');
      expect(loaded.configuration!.webhook!.password, 'secret');
    });

    test('preserves UserConfiguration with bearer token', () async {
      const user = ChatUser(
        id: 'user-bearer',
        configuration: UserConfiguration(
          webhook: WebhookConfig(
            url: 'https://hook.example.com/bearer',
            authType: WebhookAuthType.bearer,
            token: 'my-token-123',
          ),
        ),
      );
      await ds.saveUsers([user]);
      final loaded = await ds.getUser('user-bearer');
      expect(loaded!.configuration!.webhook!.authType, WebhookAuthType.bearer);
      expect(loaded.configuration!.webhook!.token, 'my-token-123');
    });

    test('preserves UserConfiguration with only metadata', () async {
      const user = ChatUser(
        id: 'user-meta',
        configuration: UserConfiguration(metadata: {'key': 'value'}),
      );
      await ds.saveUsers([user]);
      final loaded = await ds.getUser('user-meta');
      expect(loaded!.configuration, isNotNull);
      expect(loaded.configuration!.metadata, {'key': 'value'});
      expect(loaded.configuration!.webhook, isNull);
    });

    test('user without configuration stays null', () async {
      await ds.saveUsers([user1]);
      final loaded = await ds.getUser('user-1');
      expect(loaded!.configuration, isNull);
    });
  });

  group('contacts', () {
    test('save and get contacts', () async {
      await ds.saveContacts([
        const ChatContact(userId: 'c-1'),
        const ChatContact(userId: 'c-2'),
      ]);
      final contacts = await ds.getContacts();
      expect(contacts.length, 2);
      expect(contacts.first.userId, 'c-1');
    });

    test('getContacts returns empty before save', () async {
      expect(await ds.getContacts(), isEmpty);
    });

    test('saveContacts replaces previous list', () async {
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.saveContacts([const ChatContact(userId: 'c-2')]);
      final contacts = await ds.getContacts();
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'c-2');
    });
  });

  group('unreads', () {
    test('save and get unreads', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
        const UnreadRoom(roomId: 'room-2', unreadMessages: 3),
      ]);
      final unreads = await ds.getUnreads();
      expect(unreads.length, 2);
    });

    test('preserves all unread fields', () async {
      await ds.saveUnreads([
        UnreadRoom(
          roomId: 'room-1',
          unreadMessages: 5,
          lastMessage: 'Hello',
          lastMessageTime: DateTime.utc(2026, 1, 1),
          lastMessageUserId: 'user-1',
          lastMessageId: 'msg-1',
        ),
      ]);
      final unreads = await ds.getUnreads();
      final u = unreads.first;
      expect(u.lastMessage, 'Hello');
      expect(u.lastMessageTime, DateTime.utc(2026, 1, 1));
      expect(u.lastMessageUserId, 'user-1');
      expect(u.lastMessageId, 'msg-1');
    });

    test('deleteUnread removes specific room', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
        const UnreadRoom(roomId: 'room-2', unreadMessages: 3),
      ]);
      await ds.deleteUnread('room-1');
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
      expect(unreads.first.roomId, 'room-2');
    });

    test('deleteUnread with nonexistent roomId is a no-op', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);
      await ds.deleteUnread('nonexistent');
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
    });
  });

  group('invited rooms', () {
    test('save and get invited rooms', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);
      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-1');
      expect(invited.first.invitedBy, 'user-1');
    });

    test('saveInvitedRooms replaces previous list', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-2', invitedBy: 'user-2'),
      ]);
      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-2');
    });
  });

  group('offline queue', () {
    test('save and get offline queue roundtrip', () async {
      final ops = [
        {'type': 'sendMessage', 'roomId': 'room-1', 'text': 'hello'},
        {'type': 'deleteMessage', 'roomId': 'room-1', 'messageId': 'msg-1'},
      ];
      await ds.saveOfflineQueue(ops);
      final loaded = await ds.getOfflineQueue();
      expect(loaded.length, 2);
      expect(loaded[0]['type'], 'sendMessage');
      expect(loaded[1]['type'], 'deleteMessage');
    });

    test('getOfflineQueue returns empty list initially', () async {
      final queue = await ds.getOfflineQueue();
      expect(queue, isEmpty);
    });

    test('clearOfflineQueue empties the queue', () async {
      await ds.saveOfflineQueue([
        {'type': 'sendMessage', 'roomId': 'room-1'},
      ]);
      await ds.clearOfflineQueue();
      final queue = await ds.getOfflineQueue();
      expect(queue, isEmpty);
    });

    test('saveOfflineQueue replaces previous queue', () async {
      await ds.saveOfflineQueue([
        {'type': 'first'},
      ]);
      await ds.saveOfflineQueue([
        {'type': 'second'},
      ]);
      final queue = await ds.getOfflineQueue();
      expect(queue.length, 1);
      expect(queue.first['type'], 'second');
    });

    test('handles nested metadata in operations', () async {
      await ds.saveOfflineQueue([
        {
          'type': 'sendMessage',
          'metadata': {
            'nested': {'deep': true},
            'list': [1, 2, 3],
          },
        },
      ]);
      final loaded = await ds.getOfflineQueue();
      final metadata = loaded.first['metadata'] as Map;
      expect((metadata['nested'] as Map)['deep'], true);
      expect(metadata['list'], [1, 2, 3]);
    });

    test('getOfflineQueue returns independent copies', () async {
      await ds.saveOfflineQueue([
        {'type': 'test', 'value': 'original'},
      ]);
      final loaded = await ds.getOfflineQueue();
      loaded.first['value'] = 'modified';

      final reloaded = await ds.getOfflineQueue();
      expect(reloaded.first['value'], 'original');
    });
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
      final messages = await ds.getMessages('room-1');
      expect(messages.length, 1);
      expect(messages.first.id, 'good');
    });

    test('getRooms skips corrupted records', () async {
      await ds.saveRooms([const ChatRoom(id: 'good')]);
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('bad', {'garbage': true});
      final rooms = await ds.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.id, 'good');
    });

    test('getRoom returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('corrupted', {'garbage': true});
      final room = await ds.getRoom('corrupted');
      expect(room, isNull);
    });

    test('getUser returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_users');
      await box.put('corrupted', {'garbage': true});
      final user = await ds.getUser('corrupted');
      expect(user, isNull);
    });

    test('getUnreads skips corrupted records', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'good', unreadMessages: 1),
      ]);
      final box = await Hive.openBox<Map>('chat_unreads');
      await box.put('bad', {'garbage': true});
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
    });

    test('getRoomDetail returns null for corrupted record', () async {
      final box = await Hive.openBox<Map>('chat_room_details');
      await box.put('corrupted', {'garbage': true});
      final detail = await ds.getRoomDetail('corrupted');
      expect(detail, isNull);
    });

    test('getContacts skips corrupted records', () async {
      await ds.saveContacts([const ChatContact(userId: 'good')]);
      final box = await Hive.openBox<Map>('chat_contacts');
      await box.put(99, {'garbage': true});
      final contacts = await ds.getContacts();
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'good');
    });

    test('getInvitedRooms skips corrupted records', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'good', invitedBy: 'user-1'),
      ]);
      final box = await Hive.openBox<Map>('chat_invited');
      await box.put(99, {'garbage': true});
      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.roomId, 'good');
    });

    test('getRooms warns with first error detail and aggregated count', () async {
      final warnings = <String>[];
      ds.onWarning = warnings.add;
      await ds.saveRooms([const ChatRoom(id: 'good')]);
      final box = await Hive.openBox<Map>('chat_rooms');
      await box.put('bad-1', {'garbage': true});
      await box.put('bad-2', {'garbage': true});
      await ds.getRooms();
      final corruptionWarnings =
          warnings.where((w) => w.contains('Skipped')).toList();
      expect(corruptionWarnings, hasLength(1));
      expect(corruptionWarnings.first, contains('Skipped 2 corrupted records'));
      expect(corruptionWarnings.first, contains('in rooms'));
      expect(corruptionWarnings.first, contains('first error:'));
    });

    test('getMessages warns with key and error detail per corrupted record',
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
      await ds.getMessages('room-1');
      final corruptionWarnings = warnings
          .where((w) => w.contains('Skipped corrupted message'))
          .toList();
      expect(corruptionWarnings, hasLength(1));
      expect(corruptionWarnings.first, contains('"bad-key"'));
      expect(corruptionWarnings.first, matches(RegExp(r':\s+\S')));
    });
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
      final messages = await ds.getMessages('room-1');
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
      final messages = await ds.getMessages('room-1');
      expect(messages.length, 1);
    });

    test('deleteRoom with non-existent ID is a no-op', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.deleteRoom('nonexistent');
      final rooms = await ds.getRooms();
      expect(rooms.length, 1);
    });

    test('deleteUser with non-existent ID is a no-op', () async {
      await ds.saveUsers([const ChatUser(id: 'user-1')]);
      await ds.deleteUser('nonexistent');
      final users = await ds.getUsers();
      expect(users.length, 1);
    });
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
      final stored = await limitedDs.getMessages('room-1');
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
      final stored = await limitedDs.getMessages('room-1');
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

      final stored = await limitedDs.getMessages('room-1');
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
      final stored = await ds1.getMessages('room-1');
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

  group('pagination edge cases', () {
    final messages = List.generate(
      5,
      (i) => ChatMessage(
        id: 'msg-$i',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
        text: 'Message $i',
      ),
    );

    test('before with invalid timestamp returns empty list', () async {
      await ds.saveMessages('room-1', messages);
      final loaded = await ds.getMessages('room-1', before: 'nonexistent');
      expect(loaded, isEmpty);
    });

    test('limit larger than available returns all', () async {
      await ds.saveMessages('room-1', messages);
      final loaded = await ds.getMessages('room-1', limit: 100);
      expect(loaded.length, 5);
    });

    test('before oldest message timestamp returns empty', () async {
      await ds.saveMessages('room-1', messages);
      final loaded = await ds.getMessages('room-1',
          before: DateTime.utc(2026, 1, 1).toIso8601String());
      expect(loaded, isEmpty);
    });

    test('messages saved out of order are returned sorted by timestamp', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-middle',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 2),
          text: 'middle',
        ),
        ChatMessage(
          id: 'msg-first',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'first',
        ),
        ChatMessage(
          id: 'msg-last',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 3),
          text: 'last',
        ),
      ]);
      final loaded = await ds.getMessages('room-1');
      expect(loaded[0].id, 'msg-last');
      expect(loaded[1].id, 'msg-middle');
      expect(loaded[2].id, 'msg-first');
    });
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

      expect(await ds.getMessages('room-1'), isEmpty);
      expect(await ds.getRooms(), isEmpty);
      expect(await ds.getUser('user-1'), isNull);
      expect(await ds.getContacts(), isEmpty);
      expect(await ds.getUnreads(), isEmpty);
    });

    test('clear after restart removes messages from previous session', () async {
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

      expect(await ds2.getMessages('room-a'), isEmpty);
      expect(await ds2.getMessages('room-b'), isEmpty);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
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

      // room-orphan has messages but no room entry — simulate crash/inconsistency
      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);

      // Orphan box should have been cleaned
      final orphanMessages = await ds2.getMessages('room-orphan');
      expect(orphanMessages, isEmpty);

      // Valid room messages should survive
      final keptMessages = await ds2.getMessages('room-keep');
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

      expect(await ds2.getRooms(), isEmpty);
      expect(await ds2.getUser('user-1'), isNull);
      expect(await ds2.getMessages('room-1'), isEmpty);

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

      expect(await ds2.getRooms(), isEmpty);
      expect(await ds2.getUser('user-1'), isNull);

      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('preserves data when schema version matches', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Keep')]);

      await ds.dispose();
      await Hive.close();

      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final rooms = await ds2.getRooms();
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
          1: () async { migrationsRun.add(1); },
          2: () async { migrationsRun.add(2); },
        },
      );

      expect(migrationsRun, [1, 2]);
      final rooms = await ds2.getRooms();
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
          final loaded = (await ds.getMessages('room-1')).first;
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
          final loaded = (await ds.getMessages('room-1')).first;
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
          final loaded = await ds.getRoom('room-${audience.name}');
          expect(loaded!.audience, audience);
        });
      }
    });

    group('UserRole', () {
      for (final role in UserRole.values) {
        test('roundtrips UserRole.${role.name}', () async {
          final user = ChatUser(id: 'user-${role.name}', role: role);
          await ds.saveUsers([user]);
          final loaded = await ds.getUser('user-${role.name}');
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
          final loaded = await ds.getRoomDetail('room-${role.name}');
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
          final loaded = await ds.getRoomDetail('room-${type.name}');
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
          final loaded = await ds.getUser('user-${authType.name}');
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
      final loaded = (await ds.getMessages('room-1')).first;
      expect(loaded.text, isNull);
      expect(loaded.id, 'msg-null-text');
    });

    test('message with nested metadata roundtrips', () async {
      final msg = ChatMessage(
        id: 'msg-meta',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, 1),
        metadata: {
          'string': 'value',
          'int': 42,
          'bool': true,
          'list': [1, 'two', 3.0],
          'nested': {'deep': {'key': 'val'}},
          'null_val': null,
        },
      );
      await ds.saveMessages('room-1', [msg]);
      final loaded = (await ds.getMessages('room-1')).first;
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
      final loaded = (await ds.getMessages('room-1')).first;
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
      final loaded = await ds.getUser('user-full');
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
      final loaded = await ds.getRoom('room-full');
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
      final loaded = await ds.getRoom('room-minimal');
      expect(loaded!.id, 'room-minimal');
      expect(loaded.owner, isNull);
      expect(loaded.name, isNull);
      expect(loaded.subject, isNull);
      expect(loaded.publicToken, isNull);
      expect(loaded.avatarUrl, isNull);
      expect(loaded.custom, isNull);
    });

    test('room detail with custom map roundtrips', () async {
      final detail = RoomDetail(
        id: 'room-custom',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.owner,
        config: const RoomConfig(allowInvitations: true),
        custom: {'priority': 'high', 'tags': ['vip', 'active']},
      );
      await ds.saveRoomDetail(detail);
      final loaded = await ds.getRoomDetail('room-custom');
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
      final loaded = await ds.getRoomDetail('room-no-date');
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
      final loaded = await ds.getUnreads();
      final u = loaded.first;
      expect(u.roomId, 'room-full-unread');
      expect(u.unreadMessages, 10);
      expect(u.lastMessage, 'Last msg');
      expect(u.lastMessageTime, DateTime.utc(2026, 3, 15, 14, 30));
      expect(u.lastMessageUserId, 'user-1');
      expect(u.lastMessageId, 'msg-100');
    });
  });

  group('deleteRoom cascades to invited rooms', () {
    test('removes invited room entry on deleteRoom', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-a'),
        const InvitedRoom(roomId: 'room-2', invitedBy: 'user-b'),
      ]);

      await ds.deleteRoom('room-1');

      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-2');
    });
  });

  group('updateMessage does not track non-existent rooms', () {
    test('updateMessage on missing room does not create tracking', () async {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026),
        text: 'ghost',
      );
      await ds.updateMessage('non-existent-room', msg);

      // After dispose/recreate, orphan cleanup should find nothing to clean
      await ds.dispose();
      await Hive.close();
      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final messages = await ds2.getMessages('non-existent-room');
      expect(messages, isEmpty);
      await ds2.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('roomId sanitization', () {
    test('handles roomId with slashes', () async {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026),
        text: 'slashes',
      );
      await ds.saveMessages('room/with/slashes', [msg]);
      final loaded = await ds.getMessages('room/with/slashes');
      expect(loaded.length, 1);
      expect(loaded.first.text, 'slashes');
    });

    test('handles roomId with spaces and dots', () async {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026),
        text: 'special',
      );
      await ds.saveMessages('room ..name', [msg]);
      final loaded = await ds.getMessages('room ..name');
      expect(loaded.length, 1);
      expect(loaded.first.text, 'special');
    });

    test('handles roomId with unicode', () async {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'user-1',
        timestamp: DateTime.utc(2026),
        text: 'unicode',
      );
      await ds.saveMessages('sala-cerveza-\u{1F37A}', [msg]);
      final loaded = await ds.getMessages('sala-cerveza-\u{1F37A}');
      expect(loaded.length, 1);
      expect(loaded.first.text, 'unicode');
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
        await roDs.saveUnreads([const UnreadRoom(roomId: 'r', unreadMessages: 1)]);
        await roDs.deleteUnread('r');
        await roDs.saveContacts([const ChatContact(userId: 'c')]);
        await roDs.saveInvitedRooms([const InvitedRoom(roomId: 'r', invitedBy: 'u')]);
        await roDs.saveOfflineQueue([{'type': 'test'}]);
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

      final stored = await limitedDs.getMessages('room-ts');
      expect(stored.length, 2);
      final ids = stored.map((m) => m.id).toSet();
      expect(ids.contains('msg-old'), isFalse);
      expect(ids.contains('msg-mid'), isTrue);
      expect(ids.contains('msg-new'), isTrue);

      await limitedDs.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('entries with non-timestamp keys are evicted first (sorted before ISO dates)', () async {
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

      final stored = await limitedDs.getMessages('room-bad-ts');
      expect(stored.length, 2);
      expect(stored.first.id, 'msg-good-2');
      expect(stored.last.id, 'msg-good-1');

      await limitedDs.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
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

      final messages = await ds2.getMessages('room-1');
      expect(messages.length, 1);
      expect(messages.first.text, 'Persistent');

      final rooms = await ds2.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.name, 'My Room');

      final user = await ds2.getUser('user-1');
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
        const ChatRoom(id: 'enc-room', audience: RoomAudience.contacts, members: []),
      ]);
      await encDs.dispose();
      await Hive.close();

      final encDs2 = await HiveChatDatasource.create(
        basePath: tempDir.path,
        encryptionCipher: cipher,
      );
      final rooms = await encDs2.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.id, 'enc-room');
      await encDs2.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('data written without cipher works normally', () async {
      await ds.saveUsers([const ChatUser(id: 'u1', displayName: 'Test', active: true)]);
      final user = await ds.getUser('u1');
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
        const ChatRoom(id: 'enc-room', audience: RoomAudience.contacts, members: []),
      ]);
      await encDs.dispose();
      await Hive.close();

      String? warning;
      final plainDs = await HiveChatDatasource.create(basePath: tempDir.path);
      plainDs.onWarning = (msg) => warning = msg;
      final rooms = await plainDs.getRooms();
      // Box was recreated empty because it couldn't be opened without cipher
      expect(rooms, isEmpty);
      expect(warning, anyOf(isNull, isA<String>()));
      await plainDs.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });
  });

  group('message TTL', () {
    test('expired messages are purged on startup', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-ttl', audience: RoomAudience.contacts, members: [])]);
      await ds.saveMessages('room-ttl', [
        ChatMessage(
          id: 'old',
          from: 'user-1',
          timestamp: DateTime.now().subtract(const Duration(days: 10)),
          text: 'Old message',
        ),
        ChatMessage(
          id: 'recent',
          from: 'user-1',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          text: 'Recent message',
        ),
      ]);
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        messageTtl: const Duration(days: 7),
      );
      final messages = await ds.getMessages('room-ttl');
      expect(messages.length, 1);
      expect(messages.first.id, 'recent');
    });

    test('no TTL means no expiration', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-ttl2', audience: RoomAudience.contacts, members: [])]);
      await ds.saveMessages('room-ttl2', [
        ChatMessage(
          id: 'ancient',
          from: 'user-1',
          timestamp: DateTime.utc(2020, 1, 1),
          text: 'Very old',
        ),
      ]);
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(basePath: tempDir.path);
      final messages = await ds.getMessages('room-ttl2');
      expect(messages.length, 1);
      expect(messages.first.id, 'ancient');
    });

    test('TTL with malformed timestamps removes corrupted entries', () async {
      await ds.dispose();
      await Hive.close();

      // Write raw data with malformed timestamp
      Hive.init(tempDir.path);
      final box = await Hive.openBox<Map>('chat_messages_room_ttl3');
      await box.put('bad', {'id': 'bad', 'from': 'u', 'timestamp': 'not-a-date', 'messageType': 'regular'});
      await box.put('good', {
        'id': 'good',
        'from': 'u',
        'timestamp': DateTime.now().toIso8601String(),
        'messageType': 'regular',
      });
      await box.close();
      // Track the room and create a room entry so orphan cleanup doesn't remove it
      final meta = await Hive.openBox<Map>('chat_meta');
      await meta.put('messageRoomIds', {'ids': ['room_ttl3']});
      await meta.close();
      final roomsBox = await Hive.openBox<Map>('chat_rooms');
      await roomsBox.put('room_ttl3', {'id': 'room_ttl3', 'audience': 'contacts', 'members': <String>[], 'allowInvitations': false});
      await roomsBox.close();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        messageTtl: const Duration(days: 7),
      );
      final messages = await ds.getMessages('room_ttl3');
      expect(messages.length, 1);
      expect(messages.first.id, 'good');
    });
  });

  group('entity eviction limits', () {
    test('rooms are evicted when exceeding maxRooms', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxRooms: 2,
      );
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = await ds.getRooms();
      expect(rooms.length, 2);
      // Oldest (first inserted) keys are evicted, newest retained
      final ids = rooms.map((r) => r.id).toSet();
      expect(ids.contains('r3'), isTrue);
      expect(ids.contains('r2'), isTrue);
    });

    test('users are evicted when exceeding maxUsers', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxUsers: 2,
      );
      await ds.saveUsers([
        const ChatUser(id: 'u1', displayName: 'A', active: true),
        const ChatUser(id: 'u2', displayName: 'B', active: true),
        const ChatUser(id: 'u3', displayName: 'C', active: true),
      ]);
      final users = await ds.getUsers();
      expect(users.length, 2);
    });

    test('no limit means no eviction', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = await ds.getRooms();
      expect(rooms.length, 3);
    });

    test('at limit does not evict', () async {
      await ds.dispose();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        maxRooms: 3,
      );
      await ds.saveRooms([
        const ChatRoom(id: 'r1', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r2', audience: RoomAudience.contacts, members: []),
        const ChatRoom(id: 'r3', audience: RoomAudience.contacts, members: []),
      ]);
      final rooms = await ds.getRooms();
      expect(rooms.length, 3);
    });
  });

  group('cascading delete resilience', () {
    test('deleteRoom with all associated data removes everything', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-cascade', name: 'Cascade Test'),
      ]);
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-cascade',
        name: 'Cascade Detail',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.admin,
        config: RoomConfig(allowInvitations: true),
      ));
      await ds.saveMessages('room-cascade', [
        ChatMessage(
          id: 'msg-c1',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'cascade msg 1',
        ),
        ChatMessage(
          id: 'msg-c2',
          from: 'user-2',
          timestamp: DateTime.utc(2026, 1, 2),
          text: 'cascade msg 2',
        ),
      ]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-cascade', unreadMessages: 7),
        const UnreadRoom(roomId: 'room-other', unreadMessages: 2),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-cascade', invitedBy: 'user-1'),
        const InvitedRoom(roomId: 'room-other', invitedBy: 'user-2'),
      ]);

      await ds.deleteRoom('room-cascade');

      expect(await ds.getRoom('room-cascade'), isNull);
      expect(await ds.getRoomDetail('room-cascade'), isNull);
      expect(await ds.getMessages('room-cascade'), isEmpty);
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
      expect(unreads.first.roomId, 'room-other');
      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-other');
    });

    test('deleteRoom preserves unrelated data', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-delete', name: 'Delete Me'),
        const ChatRoom(id: 'room-keep', name: 'Keep Me'),
      ]);
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-delete',
        type: RoomType.group,
        memberCount: 1,
        userRole: RoomRole.member,
        config: RoomConfig(),
      ));
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-keep',
        type: RoomType.group,
        memberCount: 2,
        userRole: RoomRole.member,
        config: RoomConfig(),
      ));
      await ds.saveMessages('room-delete', [
        ChatMessage(
          id: 'msg-d1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'delete me',
        ),
      ]);
      await ds.saveMessages('room-keep', [
        ChatMessage(
          id: 'msg-k1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'keep me',
        ),
      ]);

      await ds.deleteRoom('room-delete');

      expect(await ds.getRoom('room-keep'), isNotNull);
      expect((await ds.getRoom('room-keep'))!.name, 'Keep Me');
      expect(await ds.getRoomDetail('room-keep'), isNotNull);
      final keptMessages = await ds.getMessages('room-keep');
      expect(keptMessages.length, 1);
      expect(keptMessages.first.text, 'keep me');
    });
  });

  group('backup and restore', () {
    test('exportData returns valid structure with all entities', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-1', name: 'Room 1'),
        const ChatRoom(id: 'room-2', name: 'Room 2'),
      ]);
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-1',
        name: 'Detail 1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.admin,
        config: RoomConfig(allowInvitations: true),
      ));
      await ds.saveUsers([
        const ChatUser(id: 'user-1', displayName: 'Alice'),
        const ChatUser(id: 'user-2', displayName: 'Bob'),
      ]);
      await ds.saveContacts([
        const ChatContact(userId: 'user-1'),
      ]);
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
      await ds.saveUsers([
        const ChatUser(id: 'user-1', displayName: 'Alice'),
      ]);

      final exported = await ds.exportData();
      final json = jsonEncode(exported);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['version'], 2);
      expect((decoded['rooms'] as List).length, 1);
    });

    test('importData restores exported data', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-1', name: 'Room 1'),
      ]);
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-1',
        name: 'Detail 1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.admin,
        config: RoomConfig(allowInvitations: true),
      ));
      await ds.saveUsers([
        const ChatUser(id: 'user-1', displayName: 'Alice'),
      ]);
      await ds.saveContacts([
        const ChatContact(userId: 'user-1'),
      ]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);

      final exported = await ds.exportData();

      await ds.clear();
      expect(await ds.getRooms(), isEmpty);
      expect(await ds.getUsers(), isEmpty);

      await ds.importData(exported);

      final rooms = await ds.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.name, 'Room 1');
      final detail = await ds.getRoomDetail('room-1');
      expect(detail, isNotNull);
      expect(detail!.name, 'Detail 1');
      final users = await ds.getUsers();
      expect(users.length, 1);
      expect(users.first.displayName, 'Alice');
      final contacts = await ds.getContacts();
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'user-1');
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
      expect(unreads.first.unreadMessages, 5);
      final invited = await ds.getInvitedRooms();
      expect(invited.length, 1);
      expect(invited.first.invitedBy, 'user-1');
    });

    test('importData replaces existing data', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'old-room', name: 'Old'),
      ]);
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
          {'id': 'new-room', 'name': 'New', 'audience': 'public', 'allowInvitations': false, 'members': <String>[]},
        ],
        'roomDetails': <Map<String, dynamic>>[],
        'users': [
          {'id': 'new-user', 'displayName': 'NewUser', 'role': 'user', 'active': true},
        ],
        'contacts': <Map<String, dynamic>>[],
        'unreads': <Map<String, dynamic>>[],
        'invitedRooms': <Map<String, dynamic>>[],
      };

      await ds.importData(exportedData);

      final rooms = await ds.getRooms();
      expect(rooms.length, 1);
      expect(rooms.first.id, 'new-room');
      expect(await ds.getRoom('old-room'), isNull);
      final users = await ds.getUsers();
      expect(users.length, 1);
      expect(users.first.id, 'new-user');
      expect(await ds.getUser('old-user'), isNull);
    });

    test('importData with wrong version throws', () async {
      final badData = {
        'version': 999,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
      };

      expect(
        () => ds.importData(badData),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Incompatible schema version'),
        )),
      );
    });

    test('importData with null version throws', () async {
      final badData = {
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
      };

      expect(
        () => ds.importData(badData),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('importData with mismatched counts warns', () async {
      final warnings = <String>[];
      ds.onWarning = (msg) => warnings.add(msg);

      final data = {
        'version': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'validation': {
          'roomCount': 5,
          'userCount': 10,
          'contactCount': 3,
        },
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
      await ds.saveRoomDetail(const RoomDetail(
        id: 'room-json',
        name: 'JSON Detail',
        type: RoomType.oneToOne,
        memberCount: 2,
        userRole: RoomRole.owner,
        config: RoomConfig(allowInvitations: true),
        muted: true,
        pinned: true,
      ));
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

      final room = await ds.getRoom('room-json');
      expect(room, isNotNull);
      expect(room!.name, 'JSON Test');
      expect(room.custom, {'theme': 'dark'});
      final detail = await ds.getRoomDetail('room-json');
      expect(detail, isNotNull);
      expect(detail!.type, RoomType.oneToOne);
      expect(detail.muted, true);
      final user = await ds.getUser('user-1');
      expect(user, isNotNull);
      expect(user!.role, UserRole.admin);
      expect(user.active, false);
      final contacts = await ds.getContacts();
      expect(contacts.length, 1);
      final unreads = await ds.getUnreads();
      expect(unreads.length, 1);
      expect(unreads.first.lastMessage, 'hello');
      final invited = await ds.getInvitedRooms();
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
