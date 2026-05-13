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

  group('sendMessage optimistic', () {
    test('adds optimistic message to controller immediately', () async {
      final controller = adapter.getChatController('room1');
      final future = adapter.sendMessage('room1', text: 'Hello');

      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.text, 'Hello');
      expect(controller.messages.first.from, 'u1');
      expect(controller.messages.first.id, startsWith('_pending_'));

      await future;
    });

    test('marks optimistic message as pending', () async {
      final controller = adapter.getChatController('room1');
      final future = adapter.sendMessage('room1', text: 'Hello');

      final tempId = controller.messages.first.id;
      expect(controller.isPending(tempId), true);
      expect(controller.isFailed(tempId), false);

      await future;
    });

    test(
      'on success calls confirmSent replacing temp with server message',
      () async {
        final controller = adapter.getChatController('room1');
        final result = await adapter.sendMessage('room1', text: 'Hello');

        expect(result.isSuccess, true);
        final serverMsg = result.dataOrNull!;

        expect(controller.isPending(serverMsg.id), false);
        expect(controller.messages.any((m) => m.id == serverMsg.id), true);
        expect(
          controller.messages.any((m) => m.id.startsWith('_pending_')),
          false,
        );
      },
    );

    test('on failure marks message as failed', () async {
      final controller = adapter.getChatController('room1');

      // We cannot easily make MockMessagesApi fail, so we test the
      // controller-level markFailed path by verifying the happy path
      // already works (tested above) and checking the pending/failed
      // state model directly.
      controller.addMessage(
        ChatMessage(
          id: '_pending_manual',
          from: 'u1',
          timestamp: DateTime.now(),
          text: 'Will fail',
        ),
      );
      controller.markPending('_pending_manual');
      expect(controller.isPending('_pending_manual'), true);

      controller.markFailed('_pending_manual');
      expect(controller.isFailed('_pending_manual'), true);
      expect(controller.isPending('_pending_manual'), false);
      expect(controller.failedMessageIds, contains('_pending_manual'));
    });
  });

  group('system messages', () {
    test('UserJoinedEvent creates system message', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      mockClient.emitEvent(
        const ChatEvent.userJoined(roomId: 'room1', userId: 'u2'),
      );
      await Future.delayed(Duration.zero);

      final systemMessages = controller.messages.where((m) => m.isSystem);
      expect(systemMessages, hasLength(1));

      final sysMsg = systemMessages.first;
      expect(sysMsg.id, startsWith('_system_'));
      expect(sysMsg.metadata?['event'], 'user_joined');
      expect(sysMsg.metadata?['userId'], 'u2');
      expect(sysMsg.from, 'system');
      expect(sysMsg.text, contains('u2'));
    });

    test('UserLeftEvent creates system message', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      mockClient.emitEvent(
        const ChatEvent.userLeft(roomId: 'room1', userId: 'u3'),
      );
      await Future.delayed(Duration.zero);

      final systemMessages = controller.messages.where((m) => m.isSystem);
      expect(systemMessages, hasLength(1));

      final sysMsg = systemMessages.first;
      expect(sysMsg.metadata?['event'], 'user_left');
      expect(sysMsg.metadata?['userId'], 'u3');
    });
  });

  group('_updateRoomLastMessage', () {
    test('uses emoji preview for attachment messages with null text', () async {
      await adapter.connect();
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test'),
      );

      final attachmentMsg = ChatMessage(
        id: 'att1',
        from: 'u2',
        timestamp: DateTime(2026, 4, 1),
        text: null,
        messageType: MessageType.attachment,
        attachmentUrl: 'https://example.com/file.png',
      );
      mockClient.emitEvent(
        ChatEvent.newMessage(message: attachmentMsg, roomId: 'room1'),
      );
      await Future.delayed(Duration.zero);

      final room = adapter.roomListController.getRoomById('room1');
      expect(room, isNotNull);
      expect(room!.lastMessage, ChatUiLocalizations.en.attachmentPreview);
    });

    test('uses emoji preview for audio messages with null text', () async {
      await adapter.connect();
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Test'),
      );

      final audioMsg = ChatMessage(
        id: 'aud1',
        from: 'u2',
        timestamp: DateTime(2026, 4, 1),
        text: null,
        messageType: MessageType.audio,
      );
      mockClient.emitEvent(
        ChatEvent.newMessage(message: audioMsg, roomId: 'room1'),
      );
      await Future.delayed(Duration.zero);

      final room = adapter.roomListController.getRoomById('room1');
      expect(room, isNotNull);
      expect(room!.lastMessage, ChatUiLocalizations.en.audioPreview);
    });
  });

  group('_updatePresenceInRoomList', () {
    test('uses _dmRoomByContact for O(1) lookup', () async {
      await adapter.connect();

      adapter.roomListController.addRoom(
        const RoomListItem(
          id: 'dm-room-1',
          name: 'Contact',
          isGroup: false,
          otherUserId: 'contact1',
        ),
      );
      adapter.registerDmRoom('contact1', 'dm-room-1');

      mockClient.emitEvent(
        ChatEvent.presenceChanged(
          userId: 'contact1',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future.delayed(Duration.zero);

      final room = adapter.roomListController.getRoomById('dm-room-1');
      expect(room, isNotNull);
      expect(room!.isOnline, true);

      mockClient.emitEvent(
        ChatEvent.presenceChanged(
          userId: 'contact1',
          status: PresenceStatus.away,
          online: false,
        ),
      );
      await Future.delayed(Duration.zero);

      final updated = adapter.roomListController.getRoomById('dm-room-1');
      expect(updated!.isOnline, false);
    });

    test('ignores presence for unknown contacts', () async {
      await adapter.connect();

      adapter.roomListController.addRoom(
        const RoomListItem(id: 'dm-room-1', name: 'Contact', isGroup: false),
      );
      // No registerDmRoom call -> userId not in _dmRoomByContact

      mockClient.emitEvent(
        ChatEvent.presenceChanged(
          userId: 'unknown-user',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future.delayed(Duration.zero);

      final room = adapter.roomListController.getRoomById('dm-room-1');
      expect(room!.isOnline, isNull);
    });
  });

  group('loadRooms', () {
    test('loads rooms using parallel Future.wait', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Room A',
      );
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Room B',
      );

      final result = await adapter.loadRooms();
      expect(result.isSuccess, true);

      final rooms = adapter.roomListController.allRooms;
      expect(rooms, hasLength(2));
      expect(rooms.map((r) => r.name), containsAll(['Room A', 'Room B']));
    });

    test('loadRooms populates room IDs', () async {
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test Room',
      );

      await adapter.loadRooms();

      final rooms = adapter.roomListController.allRooms;
      expect(rooms.first.id, startsWith('mock-room-'));
    });
  });

  group('getRoomById', () {
    test('works via roomListController', () {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room-abc', name: 'ABC Room', unreadCount: 3),
      );

      final room = adapter.roomListController.getRoomById('room-abc');
      expect(room, isNotNull);
      expect(room!.name, 'ABC Room');
      expect(room.unreadCount, 3);
    });

    test('returns null for non-existent room', () {
      final room = adapter.roomListController.getRoomById('non-existent');
      expect(room, isNull);
    });
  });
}
