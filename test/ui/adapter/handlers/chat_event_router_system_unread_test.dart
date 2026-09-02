import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A system-generated message (plan lifecycle notices, membership changes,
/// …) still lands in the room and updates its preview, but must not count
/// as unread: not on the per-room counter, and — by extension — not on the
/// Messaggi tab badge or the "N new messages" divider, both of which are
/// derived from this counter.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  ChatMessage systemMsg(String id, {String from = 'plan-owner'}) =>
      ChatMessage(
        id: id,
        from: from,
        timestamp: DateTime(2026, 1, 1),
        text: id,
        isSystem: true,
        metadata: const {'system': true},
      );

  ChatMessage personMsg(String id, {String from = 'u2'}) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1),
    text: id,
  );

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'Plan room', isGroup: true),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('a system message does not bump the room unread counter', () async {
    client.emitEvent(NewMessageEvent(message: systemMsg('s1'), roomId: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 0);
  });

  test(
    'four system messages in a row still leave the room read',
    () async {
      for (final id in ['s1', 's2', 's3', 's4']) {
        client.emitEvent(
          NewMessageEvent(message: systemMsg(id), roomId: 'r1'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 0);
      expect(adapter.roomListController.unreadRoomCount(), 0);
    },
  );

  test('a person message still bumps the counter as a control', () async {
    client.emitEvent(
      NewMessageEvent(message: personMsg('m1'), roomId: 'r1'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(adapter.roomListController.getRoomById('r1')!.unreadCount, 1);
    expect(adapter.roomListController.unreadRoomCount(), 1);
  });

  test('a system message still updates the room preview', () async {
    client.emitEvent(
      NewMessageEvent(message: systemMsg('s1'), roomId: 'r1'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      adapter.roomListController.getRoomById('r1')!.lastMessageId,
      's1',
    );
  });
}
