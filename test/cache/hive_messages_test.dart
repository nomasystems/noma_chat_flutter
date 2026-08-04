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
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-2');
      expect(messages.last.id, 'msg-1');
    });

    test('get messages with limit', () async {
      await ds.saveMessages('room-1', [msg1, msg2, msg3]);
      final messages = (await ds.getMessages('room-1', limit: 2)).dataOrNull!;
      expect(messages.length, 2);
      expect(messages.first.id, 'msg-3');
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
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
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
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.first.text, 'Edited');
    });

    test('delete message', () async {
      await ds.saveMessages('room-1', [msg1, msg2]);
      await ds.deleteMessage('room-1', 'msg-1');
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'msg-2');
    });

    test('clear messages', () async {
      await ds.saveMessages('room-1', [msg1, msg2]);
      await ds.clearMessages('room-1');
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
      expect(messages, isEmpty);
    });

    test('concurrent access to same room does not throw', () async {
      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        futures.add(
          ds.saveMessages('room-concurrent', [
            ChatMessage(
              id: 'msg-$i',
              from: 'user-1',
              timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
              text: 'Concurrent $i',
            ),
          ]),
        );
        futures.add(ds.getMessages('room-concurrent'));
      }
      await Future.wait(futures);
      final messages = (await ds.getMessages('room-concurrent')).dataOrNull!;
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

      final stored = (await limitedDs.getMessages('room-1')).dataOrNull!;
      expect(stored.length, 5);
      expect(stored.first.id, 'msg-9');
      expect(stored.last.id, 'msg-5');

      await limitedDs.dispose();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);
    });

    test('messages from different rooms are isolated', () async {
      await ds.saveMessages('room-1', [msg1]);
      await ds.saveMessages('room-2', [msg2]);
      expect((await ds.getMessages('room-1')).dataOrNull!.length, 1);
      expect((await ds.getMessages('room-2')).dataOrNull!.length, 1);
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
        metadata: const {'key': 'value'},
        receipt: ReceiptStatus.delivered,
        isEdited: true,
        isDeleted: true,
        isForwarded: true,
      );
      await ds.saveMessages('room-1', [fullMsg]);
      final messages = (await ds.getMessages('room-1')).dataOrNull!;
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

    test('limit larger than available returns all', () async {
      await ds.saveMessages('room-1', messages);
      final loaded = (await ds.getMessages('room-1', limit: 100)).dataOrNull!;
      expect(loaded.length, 5);
    });

    test(
      'messages saved out of order are returned sorted by timestamp',
      () async {
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
        final loaded = (await ds.getMessages('room-1')).dataOrNull!;
        expect(loaded[0].id, 'msg-last');
        expect(loaded[1].id, 'msg-middle');
        expect(loaded[2].id, 'msg-first');
      },
    );
  });

  group('receipt durability', () {
    final outgoing = ChatMessage(
      id: 'msg-r',
      from: 'user-1',
      timestamp: DateTime.utc(2026, 2, 1),
      text: 'Outgoing',
    );

    Future<ChatMessage> onlyStored(String roomId) async =>
        (await ds.getMessages(roomId)).dataOrNull!.single;

    test('a stored read survives a network row with a null receipt', () async {
      await ds.saveMessages('room-r1', [
        outgoing.copyWith(receipt: ReceiptStatus.read),
      ]);
      await ds.saveMessages('room-r1', [outgoing]);
      expect((await onlyStored('room-r1')).receipt, ReceiptStatus.read);
    });

    test('a lower receipt never replaces a higher stored one', () async {
      await ds.saveMessages('room-r2', [
        outgoing.copyWith(receipt: ReceiptStatus.read),
      ]);
      await ds.saveMessages('room-r2', [
        outgoing.copyWith(receipt: ReceiptStatus.delivered),
      ]);
      expect((await onlyStored('room-r2')).receipt, ReceiptStatus.read);
    });

    test('a higher receipt still advances the stored one', () async {
      await ds.saveMessages('room-r3', [
        outgoing.copyWith(receipt: ReceiptStatus.sent),
      ]);
      await ds.saveMessages('room-r3', [
        outgoing.copyWith(receipt: ReceiptStatus.read),
      ]);
      expect((await onlyStored('room-r3')).receipt, ReceiptStatus.read);
    });

    test('the merge follows the row when its timestamp key moves', () async {
      await ds.saveMessages('room-r4', [
        outgoing.copyWith(receipt: ReceiptStatus.read),
      ]);
      await ds.saveMessages('room-r4', [
        outgoing.copyWith(timestamp: DateTime.utc(2026, 2, 2)),
      ]);
      expect((await onlyStored('room-r4')).receipt, ReceiptStatus.read);
    });

    test('updateMessage keeps the stored receipt while editing', () async {
      await ds.saveMessages('room-r5', [
        outgoing.copyWith(receipt: ReceiptStatus.read),
      ]);
      await ds.updateMessage(
        'room-r5',
        outgoing.copyWith(text: 'Edited', isEdited: true),
      );
      final stored = await onlyStored('room-r5');
      expect(stored.text, 'Edited');
      expect(stored.receipt, ReceiptStatus.read);
    });

    test('cold start: a controller built from the reopened cache shows '
        'the double check before any network event', () async {
      const me = ChatUser(id: 'user-1');
      const peer = ChatUser(id: 'user-2');
      // The room has to be known for its message box to survive the
      // orphan sweep the next startup runs.
      await ds.saveRooms([
        const ChatRoom(
          id: 'room-cold',
          audience: RoomAudience.contacts,
          members: ['user-1', 'user-2'],
        ),
      ]);
      await ds.saveMessages('room-cold', [outgoing]);

      // What the router does when a receipt frame lands: advance the
      // controller, then write back the rows it stamped.
      final live = ChatController(
        initialMessages: [outgoing],
        currentUser: me,
        otherUsers: const [peer],
      );
      addTearDown(live.dispose);
      live.updateReceipt('msg-r', ReceiptStatus.read, fromUserId: 'user-2');
      final stamped = live.drainReceiptUpdates();
      expect(stamped.single.receipt, ReceiptStatus.read);
      await ds.saveMessages('room-cold', stamped);

      await ds.dispose();
      await Hive.close();
      ds = await HiveChatDatasource.create(basePath: tempDir.path);

      final cached = (await ds.getMessages('room-cold')).dataOrNull!;
      final cold = ChatController(
        initialMessages: cached,
        currentUser: me,
        otherUsers: const [peer],
      );
      addTearDown(cold.dispose);
      expect(cold.messages.single.receipt, ReceiptStatus.read);

      // The row the backend replays on the next sync carries no receipt.
      cold.addMessages([outgoing]);
      expect(cold.messages.single.receipt, ReceiptStatus.read);
    });

    test('draining twice does not replay the same rows', () async {
      final live = ChatController(
        initialMessages: [outgoing],
        currentUser: const ChatUser(id: 'user-1'),
        otherUsers: const [ChatUser(id: 'user-2')],
      );
      addTearDown(live.dispose);
      live.updateReceipt('msg-r', ReceiptStatus.read, fromUserId: 'user-2');
      expect(live.drainReceiptUpdates(), hasLength(1));
      expect(live.drainReceiptUpdates(), isEmpty);
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

      await ds.dispose();
      await Hive.close();
      final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
      final messages = (await ds2.getMessages('non-existent-room')).dataOrNull!;
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
      final loaded = (await ds.getMessages('room/with/slashes')).dataOrNull!;
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
      final loaded = (await ds.getMessages('room ..name')).dataOrNull!;
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
      final loaded = (await ds.getMessages(
        'sala-cerveza-\u{1F37A}',
      )).dataOrNull!;
      expect(loaded.length, 1);
      expect(loaded.first.text, 'unicode');
    });
  });

  group('message TTL', () {
    test('expired messages are purged on startup', () async {
      await ds.saveRooms([
        const ChatRoom(
          id: 'room-ttl',
          audience: RoomAudience.contacts,
          members: [],
        ),
      ]);
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
      final messages = (await ds.getMessages('room-ttl')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'recent');
    });

    test('no TTL means no expiration', () async {
      await ds.saveRooms([
        const ChatRoom(
          id: 'room-ttl2',
          audience: RoomAudience.contacts,
          members: [],
        ),
      ]);
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
      final messages = (await ds.getMessages('room-ttl2')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'ancient');
    });

    test('TTL with malformed timestamps removes corrupted entries', () async {
      await ds.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      final box = await Hive.openBox<Map>('chat_messages_room_ttl3');
      await box.put('bad', {
        'id': 'bad',
        'from': 'u',
        'timestamp': 'not-a-date',
        'messageType': 'regular',
      });
      await box.put('good', {
        'id': 'good',
        'from': 'u',
        'timestamp': DateTime.now().toIso8601String(),
        'messageType': 'regular',
      });
      await box.close();
      final meta = await Hive.openBox<Map>('chat_meta');
      await meta.put('messageRoomIds', {
        'ids': ['room_ttl3'],
      });
      await meta.close();
      final roomsBox = await Hive.openBox<Map>('chat_rooms');
      await roomsBox.put('room_ttl3', {
        'id': 'room_ttl3',
        'audience': 'contacts',
        'members': <String>[],
        'allowInvitations': false,
      });
      await roomsBox.close();
      await Hive.close();

      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        messageTtl: const Duration(days: 7),
      );
      final messages = (await ds.getMessages('room_ttl3')).dataOrNull!;
      expect(messages.length, 1);
      expect(messages.first.id, 'good');
    });
  });
}
