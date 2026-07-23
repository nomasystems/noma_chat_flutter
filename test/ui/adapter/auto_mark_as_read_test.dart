import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `autoMarkAsRead` + `setActiveRoom`.
///
/// Covers the three integration points where the adapter is supposed
/// to flush a read receipt on the consumer's behalf:
///
/// 1. After [ChatUiAdapter.loadMessages] finishes (entering the chat).
/// 2. When the active room receives a new incoming message
///    ([ChatUiAdapter.setActiveRoom] + `_onNewMessage`).
/// 3. Right before [ChatUiAdapter.removeChatController] disposes the
///    controller (leaving the chat).
///
/// Also pins the opt-out: setting `autoMarkAsRead: false` must
/// suppress every implicit flush.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  group('autoMarkAsRead = true (default)', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    test('loadMessages success triggers a markAsRead', () async {
      adapter = ChatUiAdapter(client: client, currentUser: me);
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      client.addMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'hi',
        ),
      );
      await adapter.rooms.load();

      (client.messages).resetMarkRoomAsReadCalls();
      await adapter.messages.load('r1');

      // The adapter resolves the "last non-own message" as the high
      // water mark when no explicit id is supplied — pin it.
      expect(
        (client.messages).markRoomAsReadCalls.length,
        greaterThanOrEqualTo(1),
      );
      expect((client.messages).markRoomAsReadCalls.last.roomId, 'r1');
      expect(
        (client.messages).markRoomAsReadCalls.last.lastReadMessageId,
        'm1',
      );
    });

    test('removeChatController flushes markAsRead before disposing', () async {
      adapter = ChatUiAdapter(client: client, currentUser: me);
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      await adapter.rooms.load();
      adapter.getChatController('r1');

      (client.messages).resetMarkRoomAsReadCalls();
      adapter.removeChatController('r1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect((client.messages).markRoomAsReadCalls.length, 1);
      expect((client.messages).markRoomAsReadCalls.first.roomId, 'r1');
    });

    test('setActiveRoom flushes markAsRead exactly once when the active '
        'room changes', () async {
      adapter = ChatUiAdapter(client: client, currentUser: me);
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      await adapter.rooms.load();

      (client.messages).resetMarkRoomAsReadCalls();
      adapter.setActiveRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Calling again with the same id is a no-op (idempotent guard).
      adapter.setActiveRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect((client.messages).markRoomAsReadCalls.length, 1);
      expect(adapter.activeRoomId, 'r1');

      adapter.setActiveRoom(null);
      expect(adapter.activeRoomId, isNull);
    });

    test('setActiveRoom clears the room-list unread badge optimistically, '
        'without waiting for markAsRead\'s network round-trip', () async {
      adapter = ChatUiAdapter(client: client, currentUser: me);
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      await adapter.rooms.load();

      final room = adapter.roomListController.getRoomById('r1')!;
      adapter.roomListController.updateRoom(room.copyWith(unreadCount: 5));
      expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 5);

      adapter.setActiveRoom('r1');

      // No `await` before this assertion: markAsRead is fired
      // (`unawaited`) but its network round-trip has not had a chance to
      // resolve yet — the badge must already be 0 synchronously.
      expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 0);
    });
  });

  group('autoMarkAsRead = false', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        autoMarkAsRead: false,
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    test('loadMessages does NOT trigger markAsRead', () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      client.addMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: 'u2',
          timestamp: DateTime(2026, 1, 1),
          text: 'hi',
        ),
      );
      await adapter.rooms.load();

      (client.messages).resetMarkRoomAsReadCalls();
      await adapter.messages.load('r1');

      expect((client.messages).markRoomAsReadCalls, isEmpty);
    });

    test('setActiveRoom does NOT trigger markAsRead', () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      await adapter.rooms.load();

      (client.messages).resetMarkRoomAsReadCalls();
      adapter.setActiveRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect((client.messages).markRoomAsReadCalls, isEmpty);
    });

    test('removeChatController does NOT trigger markAsRead', () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      await adapter.rooms.load();
      adapter.getChatController('r1');

      (client.messages).resetMarkRoomAsReadCalls();
      adapter.removeChatController('r1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect((client.messages).markRoomAsReadCalls, isEmpty);
    });
  });
}
