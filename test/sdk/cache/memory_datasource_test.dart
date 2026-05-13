import 'package:noma_chat/noma_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryChatLocalDatasource', () {
    late MemoryChatLocalDatasource ds;

    setUp(() {
      ds = MemoryChatLocalDatasource();
    });

    group('messages', () {
      final msg1 = ChatMessage(
        id: 'msg-1',
        from: 'u-1',
        timestamp: DateTime(2024, 1, 1),
        text: 'First',
      );
      final msg2 = ChatMessage(
        id: 'msg-2',
        from: 'u-1',
        timestamp: DateTime(2024, 1, 2),
        text: 'Second',
      );

      test('save and get messages', () async {
        await ds.saveMessages('room-1', [msg1, msg2]);
        final messages = await ds.getMessages('room-1');
        expect(messages.length, 2);
        expect(messages.first.id, 'msg-2');
      });

      test('get with limit', () async {
        await ds.saveMessages('room-1', [msg1, msg2]);
        final messages = await ds.getMessages('room-1', limit: 1);
        expect(messages.length, 1);
      });

      test('get with before cursor', () async {
        await ds.saveMessages('room-1', [msg1, msg2]);
        final messages = await ds.getMessages('room-1', before: 'msg-2');
        expect(messages.length, 1);
        expect(messages.first.id, 'msg-1');
      });

      test('delete message', () async {
        await ds.saveMessages('room-1', [msg1, msg2]);
        await ds.deleteMessage('room-1', 'msg-1');
        final messages = await ds.getMessages('room-1');
        expect(messages.length, 1);
      });

      test('clear messages', () async {
        await ds.saveMessages('room-1', [msg1]);
        await ds.clearMessages('room-1');
        final messages = await ds.getMessages('room-1');
        expect(messages, isEmpty);
      });

      test('merge deduplicates messages', () async {
        await ds.saveMessages('room-1', [msg1]);
        final msg1Updated = ChatMessage(
          id: 'msg-1',
          from: 'u-1',
          timestamp: DateTime(2024, 1, 1),
          text: 'Updated',
        );
        await ds.saveMessages('room-1', [msg1Updated]);
        final messages = await ds.getMessages('room-1');
        expect(messages.length, 1);
        expect(messages.first.text, 'Updated');
      });
    });

    group('rooms', () {
      const room = ChatRoom(id: 'room-1', name: 'Test Room');

      test('save and get rooms', () async {
        await ds.saveRooms([room]);
        final rooms = await ds.getRooms();
        expect(rooms.length, 1);
      });

      test('get room by id', () async {
        await ds.saveRooms([room]);
        final result = await ds.getRoom('room-1');
        expect(result?.id, 'room-1');
      });

      test('get nonexistent room returns null', () async {
        final result = await ds.getRoom('nonexistent');
        expect(result, isNull);
      });

      test('delete room', () async {
        await ds.saveRooms([room]);
        await ds.deleteRoom('room-1');
        expect(await ds.getRoom('room-1'), isNull);
      });
    });

    group('users', () {
      const user = ChatUser(id: 'u-1', displayName: 'Test');

      test('save and get user', () async {
        await ds.saveUsers([user]);
        final result = await ds.getUser('u-1');
        expect(result?.displayName, 'Test');
      });

      test('get nonexistent user returns null', () async {
        expect(await ds.getUser('nonexistent'), isNull);
      });
    });

    group('contacts', () {
      const contact1 = ChatContact(userId: 'c-1');

      test('save and get contacts', () async {
        await ds.saveContacts([contact1]);
        final contacts = await ds.getContacts();
        expect(contacts.length, 1);
        expect(contacts.first.userId, 'c-1');
      });

      test('getContacts returns empty before save', () async {
        expect(await ds.getContacts(), isEmpty);
      });
    });

    group('unreads', () {
      test('save and get unreads', () async {
        await ds.saveUnreads([
          const UnreadRoom(roomId: 'r-1', unreadMessages: 5),
        ]);
        final unreads = await ds.getUnreads();
        expect(unreads.length, 1);
        expect(unreads.first.unreadMessages, 5);
      });
    });

    test('clear removes everything', () async {
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'u-1',
          timestamp: DateTime(2024),
          text: 'test',
        ),
      ]);
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveUsers([const ChatUser(id: 'u-1')]);
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'r-1', unreadMessages: 1),
      ]);

      await ds.clear();

      expect(await ds.getMessages('room-1'), isEmpty);
      expect(await ds.getRooms(), isEmpty);
      expect(await ds.getUser('u-1'), isNull);
      expect(await ds.getContacts(), isEmpty);
      expect(await ds.getUnreads(), isEmpty);
    });
  });
}
