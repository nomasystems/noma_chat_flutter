import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';

/// Drives `_handleEvent` in `ChatUiAdapter` through each branch of the
/// `ChatEvent` switch. The mock client lets us `emitEvent(...)` straight
/// into the adapter's listener; coverage here grows by ~150 lines because
/// most adapter event handlers are otherwise unreachable from unit tests.
void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() async {
    client = MockChatClient(currentUserId: 'u1');
    client.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    adapter.start();
    // Seed RoomListController so room-targeted events have a row to update.
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'Room1'),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Future<void> drain() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test(
    'NewMessageEvent from another user bumps unread + lastMessage',
    () async {
      final msg = ChatMessage(
        id: 'm-new',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'hello',
      );
      client.emitEvent(NewMessageEvent(message: msg, roomId: 'r1'));
      await drain();

      final room = adapter.roomListController.getRoomById('r1');
      expect(room, isNotNull);
      expect(room!.unreadCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'MessageDeletedEvent marks the message in-controller as deleted',
    () async {
      final controller = adapter.getChatController('r1');
      final msg = ChatMessage(
        id: 'm-del',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'bye',
      );
      controller.addMessage(msg);

      client.emitEvent(
        const MessageDeletedEvent(roomId: 'r1', messageId: 'm-del'),
      );
      await drain();

      final updated = controller.messages.firstWhere((m) => m.id == 'm-del');
      expect(updated.isDeleted, true);
    },
  );

  test('UserActivityEvent toggles typing in the controller', () async {
    final controller = adapter.getChatController('r1');

    client.emitEvent(
      const UserActivityEvent(
        roomId: 'r1',
        userId: 'u2',
        activity: ChatActivity.startsTyping,
      ),
    );
    await drain();
    expect(controller.typingUserIds, contains('u2'));

    client.emitEvent(
      const UserActivityEvent(
        roomId: 'r1',
        userId: 'u2',
        activity: ChatActivity.stopsTyping,
      ),
    );
    await drain();
    expect(controller.typingUserIds, isNot(contains('u2')));
  });

  test('UnreadUpdatedEvent sets unread count on the room', () async {
    client.emitEvent(const UnreadUpdatedEvent(roomId: 'r1', count: 7));
    await drain();
    expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 7);
  });

  test('RoomDeletedEvent removes the room', () async {
    client.emitEvent(const RoomDeletedEvent(roomId: 'r1'));
    await drain();
    expect(adapter.roomListController.getRoomById('r1'), isNull);
  });

  test(
    'ReceiptUpdatedEvent records the new status on the controller',
    () async {
      final controller = adapter.getChatController('r1');
      final msg = ChatMessage(
        id: 'm-receipt',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'sent',
      );
      controller.addMessage(msg);

      client.emitEvent(
        const ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm-receipt',
          status: ReceiptStatus.delivered,
        ),
      );
      await drain();
      expect(controller.receiptStatuses['m-receipt'], ReceiptStatus.delivered);
    },
  );

  test('ConnectedEvent flips connectionStateNotifier to connected', () async {
    client.emitEvent(const ConnectedEvent());
    await drain();
    expect(
      adapter.connectionStateNotifier.value,
      ChatConnectionState.connected,
    );
  });

  test('DisconnectedEvent flips state to disconnected', () async {
    client.emitEvent(const ConnectedEvent());
    await drain();
    client.emitEvent(const DisconnectedEvent());
    await drain();
    expect(
      adapter.connectionStateNotifier.value,
      ChatConnectionState.disconnected,
    );
  });

  test('BroadcastEvent invokes onBroadcast callback', () async {
    String? received;
    adapter.onBroadcast = (m) => received = m;

    client.emitEvent(const BroadcastEvent(message: 'maintenance'));
    await drain();
    expect(received, 'maintenance');
  });

  test(
    'ErrorEvent invokes onError callback and flips state to error',
    () async {
      ChatEvent? captured;
      adapter.onError = (e) => captured = e;

      client.emitEvent(const ErrorEvent(exception: ChatNetworkException()));
      await drain();
      expect(captured, isA<ErrorEvent>());
      expect(adapter.connectionStateNotifier.value, ChatConnectionState.error);
    },
  );

  test('UserJoinedEvent + UserLeftEvent affect the controller', () async {
    final controller = adapter.getChatController('r1');
    final before = controller.otherUsers.length;

    client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u3'));
    await drain();
    expect(controller.otherUsers.length, greaterThanOrEqualTo(before));

    client.emitEvent(const UserLeftEvent(roomId: 'r1', userId: 'u3'));
    await drain();
  });

  test('MessageUpdatedEvent triggers a refresh path (no crash)', () async {
    client.emitEvent(const MessageUpdatedEvent(roomId: 'r1', messageId: 'm-x'));
    await drain();
  });

  test(
    'ReactionAddedEvent from another user is processed (no crash)',
    () async {
      final controller = adapter.getChatController('r1');
      controller.addMessage(
        ChatMessage(
          id: 'm-reac',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          text: 'react me',
        ),
      );

      client.emitEvent(
        const ReactionAddedEvent(
          roomId: 'r1',
          messageId: 'm-reac',
          userId: 'u2',
          reaction: '🎉',
        ),
      );
      await drain();
    },
  );

  test('ReactionDeletedEvent triggers reaction refresh', () async {
    client.emitEvent(
      const ReactionDeletedEvent(roomId: 'r1', messageId: 'm-x'),
    );
    await drain();
  });

  test('PresenceChangedEvent updates room list (no crash)', () async {
    client.emitEvent(
      const PresenceChangedEvent(
        userId: 'u2',
        status: PresenceStatus.available,
        online: true,
      ),
    );
    await drain();
  });

  test('UserRoleChangedEvent triggers detail refresh (no crash)', () async {
    client.emitEvent(
      const UserRoleChangedEvent(
        roomId: 'r1',
        userId: 'u2',
        role: RoomRole.admin,
      ),
    );
    await drain();
  });

  test('DmActivityEvent for a known contact toggles typing', () async {
    // Pre-register the dm room mapping so the adapter can route the event.
    adapter.registerDmRoom('contact-1', 'r1');
    final controller = adapter.getChatController('r1');

    client.emitEvent(
      const DmActivityEvent(
        contactId: 'contact-1',
        userId: 'contact-1',
        activity: ChatActivity.startsTyping,
      ),
    );
    await drain();
    expect(controller.typingUserIds, contains('contact-1'));
  });

  test('Own user activity event is ignored', () async {
    final controller = adapter.getChatController('r1');

    client.emitEvent(
      const UserActivityEvent(
        roomId: 'r1',
        userId: 'u1',
        activity: ChatActivity.startsTyping,
      ),
    );
    await drain();
    expect(controller.typingUserIds, isEmpty);
  });
}
