import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `ChatUiAdapter.forwardMessage` fan-out.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  ChatRoom room(String id, String name) => ChatRoom(id: id, name: name);

  test('forwardMessage dispatches one send per target and reports success '
      'for each', () async {
    client.seedRoom(room('src', 'Source'));
    client.seedRoom(room('t1', 'Target 1'));
    client.seedRoom(room('t2', 'Target 2'));
    client.seedRoom(room('t3', 'Target 3'));
    await adapter.rooms.load();

    final results = await adapter.messages.forward(
      sourceRoomId: 'src',
      messageId: 'msg-xyz',
      targetRoomIds: const ['t1', 't2', 't3'],
    );

    expect(results.length, 3);
    expect(results.every((r) => r.isSuccess), isTrue);

    // Each target ended up with a forwarded message in its log.
    final t1Msgs = await client.messages.list('t1');
    final t2Msgs = await client.messages.list('t2');
    final t3Msgs = await client.messages.list('t3');
    expect(t1Msgs.dataOrNull!.items.first.messageType, MessageType.forward);
    expect(t2Msgs.dataOrNull!.items.first.messageType, MessageType.forward);
    expect(t3Msgs.dataOrNull!.items.first.messageType, MessageType.forward);
    // The forwarded message references the original (msg-xyz) and
    // carries the source room id so receivers can render the
    // "forwarded from" chip via ForwardedBubble.
    for (final pageResult in [
      t1Msgs,
      t2Msgs,
      t3Msgs,
    ].map((p) => p.dataOrNull!)) {
      final forwarded = pageResult.items.first;
      expect(forwarded.referencedMessageId, 'msg-xyz');
    }
  });

  test('forwardMessage updates the target rooms\' lastMessage so the '
      'chat list reflects the forward immediately', () async {
    client.seedRoom(room('src', 'Source'));
    client.seedRoom(room('t1', 'Target 1'));
    await adapter.rooms.load();

    final before = adapter.roomListController.getRoomById('t1');
    expect(before, isNotNull);

    await adapter.messages.forward(
      sourceRoomId: 'src',
      messageId: 'msg-xyz',
      targetRoomIds: const ['t1'],
    );
    // The mock send returns a synthetic ChatMessage; the adapter's
    // _updateRoomLastMessage syncs the RoomListItem in place.
    final after = adapter.roomListController.getRoomById('t1');
    expect(after!.lastMessageType, MessageType.forward);
    expect(after.lastMessageUserId, 'me');
  });

  test('forwardMessage on an empty target list is a no-op', () async {
    client.seedRoom(room('src', 'Source'));
    await adapter.rooms.load();

    final results = await adapter.messages.forward(
      sourceRoomId: 'src',
      messageId: 'msg-xyz',
      targetRoomIds: const [],
    );
    expect(results, isEmpty);
  });

  test('forwardMessage carries extraMetadata into the send call', () async {
    client.seedRoom(room('src', 'Source'));
    client.seedRoom(room('t1', 'Target 1'));
    await adapter.rooms.load();

    await adapter.messages.forward(
      sourceRoomId: 'src',
      messageId: 'msg-xyz',
      targetRoomIds: const ['t1'],
      extraMetadata: const {'note': 'check this out'},
    );

    final t1Msgs = await client.messages.list('t1');
    expect(t1Msgs.dataOrNull!.items.first.metadata?['note'], 'check this out');
  });
}
