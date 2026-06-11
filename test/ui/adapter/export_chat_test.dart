import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(
      client: client,
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('exportChat renders text, media and a resolved name column', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;

    await client.messages.send(roomId, text: 'hello');
    await client.messages.send(roomId, text: 'world');
    await client.messages.send(
      roomId,
      messageType: MessageType.attachment,
      attachmentUrl: 'https://cdn.example.com/a.png',
    );

    final result = await adapter.messages.exportChat(
      roomId,
      displayNameFor: (id) => id == 'u1' ? 'Me' : id,
    );

    expect(result.isSuccess, true);
    final export = result.dataOrThrow;
    expect(export.roomId, roomId);
    expect(export.messageCount, 3);
    // Order can collide on identical timestamps; assert content membership.
    expect(export.text, contains('Me: hello'));
    expect(export.text, contains('Me: world'));
    expect(export.text, contains('Me: <media omitted>'));
  });

  test('exportChat returns an empty transcript for an empty room', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Empty',
      members: ['u2'],
    );
    final result = await adapter.messages.exportChat(created.dataOrThrow.id);
    expect(result.isSuccess, true);
    expect(result.dataOrThrow.messageCount, 0);
    expect(result.dataOrThrow.text, isEmpty);
  });
}
