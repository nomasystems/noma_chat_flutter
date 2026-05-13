import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// End-to-end integration test: drives the SDK through a realistic flow
/// using the `MockChatClient` so every layer (sub-APIs → adapter → UI
/// controllers) is exercised together.
void main() {
  group('Full flow (MockChatClient + NomaChat + ChatUiAdapter)', () {
    late MockChatClient client;
    late NomaChat chat;

    setUp(() async {
      client = MockChatClient(currentUserId: 'u1');
      // Seed two rooms with a couple of messages so loadRooms returns data.
      client.seedRoom(const ChatRoom(
        id: 'room-dm',
        name: 'Alice',
        audience: RoomAudience.contacts,
        members: ['u1', 'alice'],
      ));
      client.addMessage('room-dm', ChatMessage(
        id: 'm1',
        from: 'alice',
        timestamp: DateTime(2026, 5, 12, 9),
        text: 'Hello',
      ));
      client.seedRoom(const ChatRoom(
        id: 'room-group',
        name: 'Squad',
        audience: RoomAudience.contacts,
        members: ['u1', 'alice', 'bob'],
      ));
      client.addMessage('room-group', ChatMessage(
        id: 'g1',
        from: 'bob',
        timestamp: DateTime(2026, 5, 12, 10),
        text: 'Group hello',
      ));

      chat = NomaChat.fromClient(
        client: client,
        currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
      );
      await chat.connect();
      await chat.adapter.loadRooms();
    });

    tearDown(() async {
      await chat.dispose();
      await client.dispose();
    });

    test('loadRooms populates the RoomListController', () {
      expect(chat.roomListController.allRooms, hasLength(2));
      expect(
        chat.roomListController.allRooms.map((r) => r.id),
        containsAll(<String>['room-dm', 'room-group']),
      );
    });

    test('loadMessages populates ChatController for the opened room',
        () async {
      final controller = chat.adapter.getChatController('room-dm');
      await chat.adapter.loadMessages('room-dm');

      expect(controller.messages, isNotEmpty);
      expect(controller.messages.first.id, 'm1');
    });

    test('sendMessage adds an optimistic bubble and confirms', () async {
      final controller = chat.adapter.getChatController('room-dm');
      await chat.adapter.loadMessages('room-dm');
      final before = controller.messages.length;

      final result =
          await chat.adapter.sendMessage('room-dm', text: 'Hey there');

      expect(result.isSuccess, true);
      expect(controller.messages.length, greaterThan(before));
      expect(controller.messages.any((m) => m.text == 'Hey there'), true);
    });

    test('editMessage updates the bubble text', () async {
      final controller = chat.adapter.getChatController('room-dm');
      await chat.adapter.loadMessages('room-dm');

      final sent = await chat.adapter
          .sendMessage('room-dm', text: 'first version');
      final sentId = sent.dataOrNull!.id;

      await chat.adapter
          .editMessage('room-dm', sentId, text: 'edited version');

      final edited =
          controller.messages.firstWhere((m) => m.id == sentId);
      expect(edited.text, 'edited version');
    });

    test('deleteMessage removes the bubble locally', () async {
      final controller = chat.adapter.getChatController('room-dm');
      await chat.adapter.loadMessages('room-dm');

      final sent =
          await chat.adapter.sendMessage('room-dm', text: 'to delete');
      final sentId = sent.dataOrNull!.id;
      expect(controller.messages.any((m) => m.id == sentId), true);

      await chat.adapter.deleteMessage('room-dm', sentId);
      expect(controller.messages.any((m) => m.id == sentId), false);
    });

    test('pinMessage stores the pin in the ChatController', () async {
      final controller = chat.adapter.getChatController('room-dm');
      await chat.adapter.loadMessages('room-dm');

      await chat.adapter.pinMessage('room-dm', 'm1');

      expect(controller.isPinned('m1'), true);
      expect(controller.pinnedMessages.first.messageId, 'm1');
    });

    test('mute/unmute round-trip on a room', () async {
      await chat.adapter.muteRoom('room-group');
      expect(
        chat.roomListController.getRoomById('room-group')!.muted,
        true,
      );

      await chat.adapter.unmuteRoom('room-group');
      expect(
        chat.roomListController.getRoomById('room-group')!.muted,
        false,
      );
    });

    test('operationErrors stream stays silent during a happy-path flow',
        () async {
      final errors = <OperationError>[];
      final sub = chat.adapter.operationErrors.listen(errors.add);

      await chat.adapter.loadMessages('room-dm');
      await chat.adapter.sendMessage('room-dm', text: 'no errors expected');
      await chat.adapter.muteRoom('room-dm');

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(errors, isEmpty);
    });
  });
}
