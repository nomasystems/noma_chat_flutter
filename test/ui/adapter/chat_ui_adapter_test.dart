import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('lifecycle', () {
    test('connect starts listening to events', () async {
      await adapter.connect();
      expect(adapter.connectionState, ChatConnectionState.connected);
    });

    test('disconnect stops connection', () async {
      await adapter.connect();
      await adapter.disconnect();
      expect(adapter.connectionState, ChatConnectionState.disconnected);
    });
  });

  group('getChatController', () {
    test('creates controller for room', () {
      final controller = adapter.getChatController('room1');
      expect(controller.currentUser.id, 'u1');
      expect(controller.messages, isEmpty);
    });

    test('returns same controller for same room', () {
      final c1 = adapter.getChatController('room1');
      final c2 = adapter.getChatController('room1');
      expect(identical(c1, c2), true);
    });

    test('removeChatController disposes it', () {
      adapter.getChatController('room1');
      adapter.removeChatController('room1');
      final c2 = adapter.getChatController('room1');
      expect(c2.messages, isEmpty);
    });
  });

  group('event handling', () {
    test('newMessage event adds to chat controller', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      final msg = ChatMessage(
        id: 'msg1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'Hello',
      );
      mockClient.emitEvent(ChatEvent.newMessage(message: msg, roomId: 'room1'));

      await Future.delayed(Duration.zero);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.text, 'Hello');
    });

    test('messageUpdated event fetches and updates controller', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      final msg = ChatMessage(
        id: 'msg1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'Hi',
      );
      controller.addMessage(msg);

      final updated = ChatMessage(
        id: 'msg1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'Updated',
      );
      mockClient.addMessage('room1', updated);

      mockClient.emitEvent(
        const ChatEvent.messageUpdated(roomId: 'room1', messageId: 'msg1'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.messages.first.text, 'Updated');
    });

    test('messageDeleted event marks message as deleted (tombstone)', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hi',
        ),
      );

      mockClient.emitEvent(
        const ChatEvent.messageDeleted(roomId: 'room1', messageId: 'msg1'),
      );

      await Future.delayed(Duration.zero);
      expect(controller.messages, hasLength(1));
      final msg = controller.messages.first;
      expect(msg.id, 'msg1');
      expect(msg.isDeleted, isTrue);
      expect(msg.text, isEmpty);
    });

    test('userActivity event sets typing', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      mockClient.emitEvent(
        const ChatEvent.userActivity(
          roomId: 'room1',
          userId: 'u2',
          activity: ChatActivity.startsTyping,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(controller.typingUserIds, ['u2']);

      mockClient.emitEvent(
        const ChatEvent.userActivity(
          roomId: 'room1',
          userId: 'u2',
          activity: ChatActivity.stopsTyping,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(controller.typingUserIds, isEmpty);
    });

    test('unreadUpdated event updates room list', () async {
      await adapter.connect();
      adapter.roomListController.addRoom(
        RoomListItem(id: 'room1', name: 'Test', unreadCount: 0),
      );

      mockClient.emitEvent(
        const ChatEvent.unreadUpdated(roomId: 'room1', count: 5),
      );

      await Future.delayed(Duration.zero);
      final room = adapter.roomListController.allRooms.first;
      expect(room.unreadCount, 5);
    });

    test(
      'roomDeleted event removes from list and disposes controller',
      () async {
        await adapter.connect();
        adapter.roomListController.addRoom(RoomListItem(id: 'room1'));
        adapter.getChatController('room1');

        mockClient.emitEvent(const ChatEvent.roomDeleted(roomId: 'room1'));

        await Future.delayed(Duration.zero);
        expect(adapter.roomListController.allRooms, isEmpty);
      },
    );

    test('roomCreated event adds room AFTER successful detail fetch', () async {
      await adapter.connect();
      mockClient.seedRoom(
        ChatRoom(
          id: 'new-room',
          owner: 'u1',
          name: 'Seeded Room',
          audience: RoomAudience.unrestricted,
          members: const ['u1', 'u2'],
        ),
      );

      mockClient.emitEvent(const ChatEvent.roomCreated(roomId: 'new-room'));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(adapter.roomListController.allRooms, hasLength(1));
      expect(adapter.roomListController.allRooms.first.id, 'new-room');
      // The room must arrive enriched, not as a placeholder.
      expect(adapter.roomListController.allRooms.first.name, 'Seeded Room');
    });

    test(
      'roomCreated event does NOT add a ghost room when detail fails',
      () async {
        await adapter.connect();
        // No seedRoom call: the mock will return Failure(NotFoundFailure()).

        mockClient.emitEvent(const ChatEvent.roomCreated(roomId: 'ghost-room'));

        await Future.delayed(const Duration(milliseconds: 50));
        expect(
          adapter.roomListController.allRooms,
          isEmpty,
          reason:
              'Without a successful detail fetch, no placeholder/ghost row '
              'should appear in the room list',
        );
      },
    );

    test('newMessage updates room list last message', () async {
      await adapter.connect();
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      final msg = ChatMessage(
        id: 'msg1',
        from: 'u2',
        timestamp: DateTime(2026, 3, 15),
        text: 'Latest message',
      );
      mockClient.emitEvent(ChatEvent.newMessage(message: msg, roomId: 'room1'));

      await Future.delayed(Duration.zero);
      final room = adapter.roomListController.allRooms.first;
      expect(room.lastMessage, 'Latest message');
      expect(room.lastMessageTime, DateTime(2026, 3, 15));
    });
  });

  group('SDK actions', () {
    test('sendMessage calls SDK', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test',
      );

      final result = await adapter.sendMessage('mock-room-0', text: 'Hello');
      expect(result.isSuccess, true);
    });

    test('sendTyping calls SDK', () async {
      final result = await adapter.sendTyping('room1');
      expect(result.isSuccess, true);
    });

    test('markAsRead calls SDK', () async {
      final result = await adapter.markAsRead('room1');
      expect(result.isSuccess, true);
    });

    test('muteRoom calls SDK', () async {
      final result = await adapter.muteRoom('room1');
      expect(result.isSuccess, true);
    });

    test('pinRoom calls SDK', () async {
      final result = await adapter.pinRoom('room1');
      expect(result.isSuccess, true);
    });
  });
}
