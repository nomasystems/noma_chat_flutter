import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The first event a device ever sees for a room it doesn't know yet takes
/// the `addFromDetail` path (fetch the detail, then build a fresh
/// `RoomListItem`) rather than the `getRoomById != null` update path — a
/// system message must not seed that fresh row with an unread badge either.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  ChatMessage systemMsg(String id, {String from = 'plan-owner'}) => ChatMessage(
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
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Plan room', members: ['me', 'u2']),
    );
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('a system message about a room the device has never seen adds it '
      'without an unread badge', () async {
    client.emitEvent(NewMessageEvent(message: systemMsg('s1'), roomId: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final room = adapter.roomListController.getRoomById('r1');
    expect(room, isNotNull);
    expect(room!.unreadCount, 0);
    expect(room.lastMessageId, 's1');
  });

  test('a person message about a room the device has never seen still adds it '
      'with the badge, as a control', () async {
    client.emitEvent(NewMessageEvent(message: personMsg('m1'), roomId: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final room = adapter.roomListController.getRoomById('r1');
    expect(room, isNotNull);
    expect(room!.unreadCount, 1);
  });
}
