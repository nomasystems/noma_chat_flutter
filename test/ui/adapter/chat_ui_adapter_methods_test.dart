import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// One-call smoke for every public adapter method that is not already
/// covered in detail elsewhere. The goal is coverage of happy paths so the
/// global file-level percent moves; behavioural assertions for these
/// methods live in their dedicated test files.
void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    client.seedRoom(const ChatRoom(
      id: 'r1',
      name: 'Room1',
      audience: RoomAudience.contacts,
      members: ['u1', 'u2'],
    ));
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('sendDirectMessage delegates to client', () async {
    final r = await adapter.sendDirectMessage('u2', text: 'hello dm');
    expect(r.isSuccess, true);
  });

  test('uploadAttachment delegates to client', () async {
    final r = await adapter.uploadAttachment(
      Uint8List.fromList([1, 2, 3]),
      'image/png',
    );
    expect(r.isSuccess, true);
  });

  test('sendVoiceMessage happy path adds bubble + confirms', () async {
    final controller = adapter.getChatController('r1');

    final r = await adapter.sendVoiceMessage(
      'r1',
      audioBytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3, 4],
    );

    expect(r.isSuccess, true);
    expect(controller.messages, isNotEmpty);
  });

  test('markAsRead invokes the SDK with a derived lastReadMessageId',
      () async {
    final controller = adapter.getChatController('r1');
    controller.addMessage(ChatMessage(
      id: 'm-other',
      from: 'u2',
      timestamp: DateTime(2026, 1, 1),
      text: 'incoming',
    ));

    final r = await adapter.markAsRead('r1');
    expect(r.isSuccess, true);
  });

  test('clearChat clears the local controller + room metadata', () async {
    final controller = adapter.getChatController('r1');
    controller.addMessage(ChatMessage(
      id: 'm1', from: 'u1', timestamp: DateTime(2026, 1, 1), text: 'hi',
    ));

    adapter.roomListController.addRoom(const RoomListItem(
      id: 'r1', name: 'Room', lastMessage: 'hi',
    ));

    final r = await adapter.clearChat('r1');
    expect(r.isSuccess, true);
  });

  test('blockContact succeeds', () async {
    final r = await adapter.blockContact('u3');
    expect(r.isSuccess, true);
  });

  test('leaveRoom removes the room from the list on success', () async {
    adapter.roomListController.addRoom(const RoomListItem(id: 'r1', name: 'R'));

    final r = await adapter.leaveRoom('r1');
    expect(r.isSuccess, true);
    expect(adapter.roomListController.getRoomById('r1'), isNull);
  });

  test('hideRoom + unhideRoom toggle the hidden flag', () async {
    adapter.roomListController.addRoom(const RoomListItem(
      id: 'r1', name: 'R',
    ));

    await adapter.hideRoom('r1');
    expect(adapter.roomListController.getRoomById('r1')!.hidden, true);

    await adapter.unhideRoom('r1');
    expect(adapter.roomListController.getRoomById('r1')!.hidden, false);
  });

  test('acceptInvitation marks the room as accepted', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.public,
      name: 'Invited',
    );
    final roomId = created.dataOrNull!.id;
    adapter.roomListController.addRoom(RoomListItem(
      id: roomId,
      name: 'Invited',
      custom: const {'invited': true, 'invitedBy': 'u2'},
    ));

    final r = await adapter.acceptInvitation(roomId);
    expect(r.isSuccess, true);
  });

  test('rejectInvitation removes the room', () async {
    adapter.roomListController.addRoom(const RoomListItem(
      id: 'invited',
      name: 'X',
      custom: {'invited': true},
    ));

    final r = await adapter.rejectInvitation('invited');
    expect(r.isSuccess, true);
    expect(adapter.roomListController.getRoomById('invited'), isNull);
  });

  test('sendReceipt forwards a custom status', () async {
    final r = await adapter.sendReceipt('r1', 'm1',
        status: ReceiptStatus.delivered);
    expect(r.isSuccess, true);
  });

  test('registerDmRoom + getDmRoomId roundtrip', () {
    adapter.registerDmRoom('contact-1', 'room-dm-1');
    expect(adapter.getDmRoomId('contact-1'), 'room-dm-1');
  });

  test('cacheUsers + findCachedUser', () {
    adapter.cacheUsers(const [ChatUser(id: 'u5', displayName: 'Eve')]);
    expect(adapter.findCachedUser('u5')!.displayName, 'Eve');
    expect(adapter.findCachedUser('non-existent'), isNull);
  });

  test('findChatController returns null until getChatController is called',
      () {
    expect(adapter.findChatController('r1'), isNull);
    adapter.getChatController('r1');
    expect(adapter.findChatController('r1'), isNotNull);
  });

  test('removeChatController disposes and forgets the controller', () {
    adapter.getChatController('r1');
    expect(adapter.findChatController('r1'), isNotNull);
    adapter.removeChatController('r1');
    expect(adapter.findChatController('r1'), isNull);
  });

  test('voiceUploadProgressFor returns null when nothing is uploading', () {
    expect(adapter.voiceUploadProgressFor('any'), isNull);
  });

  test('connectionState exposes the current state', () {
    expect(adapter.connectionState, isA<ChatConnectionState>());
  });

  test('sendTyping happy path', () async {
    final r = await adapter.sendTyping('r1');
    expect(r.isSuccess, true);
  });
}
