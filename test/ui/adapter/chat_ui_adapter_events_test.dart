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

  group('receipt events', () {
    test('receiptUpdated updates controller receipt status', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'Hello',
        ),
      );

      mockClient.emitEvent(
        const ChatEvent.receiptUpdated(
          roomId: 'room1',
          messageId: 'msg1',
          status: ReceiptStatus.read,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(controller.receiptStatuses['msg1'], ReceiptStatus.read);
    });
  });

  group('reaction events', () {
    test('reactionAdded triggers refresh from server '
        '(mock returns empty so any existing entry is cleared)', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      controller.addReaction('msg1', '👎');
      expect(controller.reactions['msg1'], isNotNull);

      mockClient.emitEvent(
        const ChatEvent.reactionAdded(
          roomId: 'room1',
          messageId: 'msg1',
          userId: 'u2',
          reaction: '👍',
        ),
      );

      await Future.delayed(Duration.zero);
      expect(controller.reactions['msg1'], isNull);
    });

    test('reactionDeleted refreshes reactions from server', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      controller.addReaction('msg1', '👍');

      mockClient.emitEvent(
        const ChatEvent.reactionDeleted(roomId: 'room1', messageId: 'msg1'),
      );

      // _refreshReactions is async (fetches from server), needs extra tick
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(controller.reactions.containsKey('msg1'), false);
    });
  });

  group('DM activity events', () {
    test('dmActivity sets typing via contact-to-room mapping', () async {
      await adapter.connect();
      adapter.registerDmRoom('u2', 'dm-room');
      final controller = adapter.getChatController('dm-room');

      mockClient.emitEvent(
        const ChatEvent.dmActivity(
          contactId: 'u2',
          userId: 'u2',
          activity: ChatActivity.startsTyping,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(controller.typingUserIds, ['u2']);
    });

    test('dmActivity ignored when no room mapping', () async {
      await adapter.connect();
      adapter.getChatController('dm-room');

      mockClient.emitEvent(
        const ChatEvent.dmActivity(
          contactId: 'unknown',
          userId: 'u3',
          activity: ChatActivity.startsTyping,
        ),
      );

      await Future.delayed(Duration.zero);
      // No crash, just ignored
    });
  });

  group('connection events', () {
    test('connectedEvent updates connectionStateNotifier', () async {
      await adapter.connect();

      mockClient.emitEvent(const ChatEvent.connected());

      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.connected,
      );
    });

    test('disconnectedEvent updates connectionStateNotifier', () async {
      await adapter.connect();

      mockClient.emitEvent(const ChatEvent.disconnected());

      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.disconnected,
      );
    });
  });

  group('broadcast events', () {
    test('broadcast calls onBroadcast callback', () async {
      await adapter.connect();
      String? received;
      adapter.onBroadcast = (msg) => received = msg;

      mockClient.emitEvent(const ChatEvent.broadcast(message: 'Hello all'));

      await Future.delayed(Duration.zero);
      expect(received, 'Hello all');
    });
  });

  group('connection state notifier', () {
    test('events update connectionStateNotifier', () async {
      await adapter.connect();

      // Wait for any initial state changes to settle
      await Future.delayed(Duration.zero);

      mockClient.emitEvent(const ChatEvent.disconnected());
      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.disconnected,
      );

      mockClient.emitEvent(const ChatEvent.connected());
      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.connected,
      );
    });
  });

  group('user role changed events', () {
    test(
      'userRoleChanged refreshes room detail and adds system message',
      () async {
        await adapter.connect();
        final controller = adapter.getChatController('room1');

        adapter.roomListController.setRooms([
          const RoomListItem(id: 'room1', name: 'Test Room'),
        ]);

        mockClient.emitEvent(
          const ChatEvent.userRoleChanged(
            roomId: 'room1',
            userId: 'u2',
            role: RoomRole.admin,
          ),
        );

        await Future.delayed(Duration.zero);
        // System message should have been added
        final systemMsg = controller.messages
            .where((m) => m.isSystem)
            .firstOrNull;
        expect(systemMsg, isNotNull);
        expect(systemMsg!.text, contains('u2'));
      },
    );
  });

  group('adapter methods', () {
    test('sendMessage with attachmentUrl passes through', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test',
      );

      final result = await adapter.sendMessage(
        'mock-room-0',
        text: 'Photo',
        attachmentUrl: 'https://example.com/photo.jpg',
      );
      expect(result.isSuccess, true);
    });

    test('editMessage with metadata passes through', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test',
      );
      final sendResult = await adapter.sendMessage(
        'mock-room-0',
        text: 'Original',
      );
      final msgId = sendResult.dataOrNull!.id;

      final result = await adapter.editMessage(
        'mock-room-0',
        msgId,
        text: 'Edited',
        metadata: {'edited': true},
      );
      expect(result.isSuccess, true);
    });

    test('sendReceipt calls SDK', () async {
      final result = await adapter.sendReceipt(
        'room1',
        'msg1',
        status: ReceiptStatus.read,
      );
      expect(result.isSuccess, true);
    });
  });
}
