import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Smokes every sub-API of MockChatClient — covers many small branches
/// in the mock that aren't exercised by `mock_chat_client_test.dart`.
void main() {
  late MockChatClient c;

  setUp(() => c = MockChatClient(currentUserId: 'u1'));
  tearDown(() async => await c.dispose());

  test('users.update + users.delete', () async {
    final upd = await c.users.update('u1', displayName: 'New');
    expect(upd.isSuccess, true);

    final del = await c.users.delete('u1');
    expect(del.isSuccess, true);
  });

  test('rooms full lifecycle: create + get + getUserRooms + delete',
      () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'Room',
    );
    final id = created.dataOrNull!.id;
    expect((await c.rooms.get(id)).isSuccess, true);
    expect((await c.rooms.getUserRooms()).isSuccess, true);
    expect((await c.rooms.delete(id)).isSuccess, true);
  });

  test('rooms mute/unmute/pin/unpin/hide/unhide/updateConfig', () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'R',
    );
    final id = created.dataOrNull!.id;
    expect((await c.rooms.mute(id)).isSuccess, true);
    expect((await c.rooms.unmute(id)).isSuccess, true);
    expect((await c.rooms.pin(id)).isSuccess, true);
    expect((await c.rooms.unpin(id)).isSuccess, true);
    expect((await c.rooms.hide(id)).isSuccess, true);
    expect((await c.rooms.unhide(id)).isSuccess, true);
    expect(
      (await c.rooms.updateConfig(id, name: 'Renamed')).isSuccess,
      true,
    );
  });

  test('rooms discover / batchMarkAsRead / batchGetUnread', () async {
    expect((await c.rooms.discover('q')).isSuccess, true);
    expect((await c.rooms.batchMarkAsRead(['r1', 'r2'])).isSuccess, true);
    expect((await c.rooms.batchGetUnread(['r1'])).isSuccess, true);
  });

  test('members lifecycle on a created room', () async {
    final created = await c.rooms
        .create(audience: RoomAudience.public, name: 'R', members: ['u2']);
    final id = created.dataOrNull!.id;
    expect(
      (await c.members.add(id, userIds: ['u3'], mode: RoomUserMode.invite))
          .isSuccess,
      true,
    );
    expect((await c.members.list(id)).isSuccess, true);
    expect((await c.members.remove(id, 'u3')).isSuccess, true);
    expect(
      (await c.members.updateRole(id, 'u2', RoomRole.admin)).isSuccess,
      true,
    );
    expect((await c.members.ban(id, 'u2')).isSuccess, true);
    expect((await c.members.unban(id, 'u2')).isSuccess, true);
    expect((await c.members.muteUser(id, 'u2')).isSuccess, true);
    expect((await c.members.unmuteUser(id, 'u2')).isSuccess, true);
  });

  test('messages.update + delete + sendReceipt + markRoomAsRead', () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'R',
    );
    final id = created.dataOrNull!.id;
    final sent = await c.messages.send(id, text: 'hi');
    final msgId = sent.dataOrNull!.id;

    expect(
      (await c.messages.update(id, msgId, text: 'edited')).isSuccess,
      true,
    );
    expect(
      (await c.messages.sendReceipt(id, msgId)).isSuccess,
      true,
    );
    expect((await c.messages.markRoomAsRead(id)).isSuccess, true);
    expect((await c.messages.getRoomReceipts(id)).isSuccess, true);
    expect((await c.messages.delete(id, msgId)).isSuccess, true);
  });

  test('messages pin/unpin/listPins + reactions + getThread', () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'R',
    );
    final id = created.dataOrNull!.id;
    final sent = await c.messages.send(id, text: 'hi');
    final msgId = sent.dataOrNull!.id;

    expect((await c.messages.pinMessage(id, msgId)).isSuccess, true);
    expect((await c.messages.listPins(id)).isSuccess, true);
    expect((await c.messages.unpinMessage(id, msgId)).isSuccess, true);

    expect(
      (await c.messages.send(id,
              messageType: MessageType.reaction,
              reaction: '👍',
              referencedMessageId: msgId))
          .isSuccess,
      true,
    );
    expect((await c.messages.getReactions(id, msgId)).isSuccess, true);
    expect((await c.messages.deleteReaction(id, msgId)).isSuccess, true);

    expect((await c.messages.getThread(id, msgId)).isSuccess, true);
  });

  test('messages.report + scheduling lifecycle', () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'R',
    );
    final id = created.dataOrNull!.id;
    final sent = await c.messages.send(id, text: 'hi');
    final msgId = sent.dataOrNull!.id;

    expect(
      (await c.messages.report(id, msgId, reason: 'spam')).isSuccess,
      true,
    );
    expect((await c.messages.listReports(id)).isSuccess, true);

    final s = await c.messages.schedule(
      id,
      sendAt: DateTime(2026, 12, 1),
      text: 'later',
    );
    expect(s.isSuccess, true);
    expect((await c.messages.listScheduled(id)).isSuccess, true);
    expect(
      (await c.messages.cancelScheduled(id, s.dataOrNull!.id)).isSuccess,
      true,
    );
  });

  test('messages.sendTyping fires via the transport-less fallback',
      () async {
    final created = await c.rooms.create(
      audience: RoomAudience.public,
      name: 'R',
    );
    expect(
      (await c.messages.sendTyping(created.dataOrNull!.id)).isSuccess,
      true,
    );
  });

  test('contacts lifecycle: add + remove + presence + DM + block list',
      () async {
    expect((await c.contacts.add('alice')).isSuccess, true);
    expect((await c.contacts.list()).isSuccess, true);
    expect((await c.contacts.getPresence('alice')).isSuccess, true);
    expect(
      (await c.contacts.sendDirectMessage('alice', text: 'hi')).isSuccess,
      true,
    );
    expect((await c.contacts.getDirectMessages('alice')).isSuccess, true);
    expect((await c.contacts.block('alice')).isSuccess, true);
    expect((await c.contacts.listBlocked()).isSuccess, true);
    expect((await c.contacts.unblock('alice')).isSuccess, true);
    expect((await c.contacts.remove('alice')).isSuccess, true);
  });

  test('contacts.sendTyping via fallback', () async {
    expect((await c.contacts.sendTyping('alice')).isSuccess, true);
  });

  test('presence update + getAll + getOwn', () async {
    expect(
      (await c.presence.update(status: PresenceStatus.busy)).isSuccess,
      true,
    );
    expect((await c.presence.getAll()).isSuccess, true);
    expect((await c.presence.getOwn()).isSuccess, true);
  });

  test('logout clears + dispose', () async {
    await c.logout();
    // dispose runs in tearDown automatically.
  });
}
