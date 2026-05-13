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

  group('Thread', () {
    test('loadThread returns messages and creates controller', () async {
      final msg = ChatMessage(
        id: 'msg1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'Hello',
      );
      mockClient.addMessage('room1', msg);

      final result = await adapter.loadThread('room1', 'msg1');

      expect(result.isSuccess, true);
      expect(result.dataOrNull, isNotEmpty);

      final controller = adapter.getChatController('thread_room1_msg1');
      expect(controller, isNotNull);
    });

    test('sendThreadReply sends with referencedMessageId', () async {
      adapter.getChatController('room1');
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      final result = await adapter.sendThreadReply(
        'room1',
        'parent1',
        text: 'Thread reply',
      );

      expect(result.isSuccess, true);
      expect(result.dataOrNull?.text, 'Thread reply');
    });
  });

  group('Search', () {
    test(
      'searchMessages delegates to SDK and returns paginated response',
      () async {
        final result = await adapter.searchMessages(
          'hello',
          'room1',
          pagination: const PaginationParams(limit: 10),
        );

        expect(result.isSuccess, true);
        expect(result.dataOrNull, isA<PaginatedResponse<ChatMessage>>());
        expect(result.dataOrNull!.items, isA<List<ChatMessage>>());
      },
    );

    test('searchMessages uses default pagination when null', () async {
      final result = await adapter.searchMessages('hello', 'room1');

      expect(result.isSuccess, true);
      expect(result.dataOrNull, isA<PaginatedResponse<ChatMessage>>());
    });

    test(
      'searchMessages is compatible with MessageSearchController.searchFn',
      () async {
        final controller = MessageSearchController(
          searchFn: adapter.searchMessages,
        );

        await controller.search('hello', 'room1');

        expect(controller.query, 'hello');
        expect(controller.isLoading, false);
        controller.dispose();
      },
    );
  });

  group('Read Receipts', () {
    test('loadReceipts delegates to SDK', () async {
      final result = await adapter.loadReceipts('room1');

      expect(result.isSuccess, true);
      expect(result.dataOrNull, isA<List<ReadReceipt>>());
    });
  });

  group('Invitations', () {
    test('acceptInvitation calls members.add and updates room', () async {
      final createResult = await mockClient.rooms.create(
        audience: RoomAudience.public,
        name: 'Invited Room',
      );
      final roomId = createResult.dataOrNull!.id;
      adapter.roomListController.addRoom(
        RoomListItem(
          id: roomId,
          name: 'Invited Room',
          custom: const {'invited': true, 'invitedBy': 'u2'},
        ),
      );

      final result = await adapter.acceptInvitation(roomId);
      expect(result.isSuccess, true);

      final room = adapter.roomListController.getRoomById(roomId);
      expect(room?.isInvitation, false);
    });

    test('rejectInvitation removes room from list', () async {
      adapter.roomListController.addRoom(
        RoomListItem(
          id: 'invited-room',
          name: 'Invited',
          custom: {'invited': true},
        ),
      );

      final result = await adapter.rejectInvitation('invited-room');
      expect(result.isSuccess, true);
      expect(adapter.roomListController.getRoomById('invited-room'), isNull);
    });
  });

  group('Message Pins', () {
    test('pinMessage delegates to SDK', () async {
      final result = await adapter.pinMessage('room1', 'msg1');
      expect(result.isSuccess, true);
    });

    test('unpinMessage delegates to SDK', () async {
      final result = await adapter.unpinMessage('room1', 'msg1');
      expect(result.isSuccess, true);
    });

    test('loadPins delegates to SDK', () async {
      final result = await adapter.loadPins('room1');
      expect(result.isSuccess, true);
      expect(result.dataOrNull, isA<List<MessagePin>>());
    });
  });
}
