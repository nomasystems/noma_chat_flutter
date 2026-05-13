import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('adapter -> controller -> widget pipeline', () {
    test('new message event flows from adapter to controller', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      expect(controller.messages, isEmpty);

      final msg = ChatMessage(
        id: 'msg1',
        from: 'u2',
        text: 'Hello from adapter pipeline',
        timestamp: DateTime(2026, 1, 1),
      );
      mockClient.emitEvent(ChatEvent.newMessage(message: msg, roomId: 'room1'));

      await Future.delayed(Duration.zero);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.first.text, 'Hello from adapter pipeline');
    });

    test('multiple events flow correctly', () async {
      await adapter.connect();
      final controller = adapter.getChatController('room1');
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      for (var i = 0; i < 3; i++) {
        mockClient.emitEvent(
          ChatEvent.newMessage(
            message: ChatMessage(
              id: 'msg$i',
              from: 'u2',
              text: 'Message $i',
              timestamp: DateTime(2026, 1, 1, 0, i),
            ),
            roomId: 'room1',
          ),
        );
      }

      await Future.delayed(Duration.zero);
      expect(controller.messages, hasLength(3));
    });

    testWidgets('controller message renders in ChatView', (tester) async {
      final controller = adapter.getChatController('room1');

      controller.addMessage(
        ChatMessage(
          id: 'msg1',
          from: 'u2',
          text: 'Pre-loaded message',
          timestamp: DateTime(2026, 1, 1),
        ),
      );

      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );

      expect(find.textContaining('Pre-loaded message'), findsOneWidget);
    });

    testWidgets(
      'ChatView shows empty state then shows message after controller update',
      (tester) async {
        final controller = adapter.getChatController('room1');

        await tester.pumpWidget(
          wrap(ChatView(controller: controller, onSendMessage: (_) {})),
        );

        expect(find.text('No messages yet'), findsOneWidget);

        controller.addMessage(
          ChatMessage(
            id: 'msg1',
            from: 'u2',
            text: 'Added after render',
            timestamp: DateTime(2026, 1, 1),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Added after render'), findsOneWidget);
        expect(find.text('No messages yet'), findsNothing);
      },
    );

    testWidgets('full pipeline: adapter event -> controller -> widget render', (
      tester,
    ) async {
      adapter.start();
      final controller = adapter.getChatController('room1');
      adapter.roomListController.addRoom(RoomListItem(id: 'room1'));

      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );

      expect(find.text('No messages yet'), findsOneWidget);

      mockClient.emitEvent(
        ChatEvent.newMessage(
          message: ChatMessage(
            id: 'msg1',
            from: 'u2',
            text: 'Full pipeline message',
            timestamp: DateTime(2026, 1, 1),
          ),
          roomId: 'room1',
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Full pipeline message'), findsOneWidget);
    });

    testWidgets('system message from user joined renders in widget', (
      tester,
    ) async {
      adapter.start();
      final controller = adapter.getChatController('room1');

      await tester.pumpWidget(
        wrap(ChatView(controller: controller, onSendMessage: (_) {})),
      );

      mockClient.emitEvent(
        const ChatEvent.userJoined(roomId: 'room1', userId: 'user42'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('user42 joined'), findsOneWidget);
    });

    test('loadRooms populates room list controller', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test Room',
      );

      adapter.start();
      final result = await adapter.loadRooms();

      expect(result.isSuccess, true);
      expect(adapter.roomListController.allRooms, hasLength(1));
      expect(adapter.roomListController.allRooms.first.name, 'Test Room');
    });

    test('sendMessage adds optimistic then confirms', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test',
      );

      adapter.start();
      final controller = adapter.getChatController('mock-room-0');

      final result = await adapter.sendMessage(
        'mock-room-0',
        text: 'Optimistic msg',
      );

      expect(result.isSuccess, true);
      expect(controller.messages.any((m) => m.text == 'Optimistic msg'), true);
    });

    test('loadMessages populates controller', () async {
      await mockClient.connect();
      await mockClient.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test',
      );

      final sendResult = await mockClient.messages.send(
        'mock-room-0',
        text: 'Existing message',
      );
      expect(sendResult.isSuccess, true);

      adapter.start();
      final result = await adapter.loadMessages('mock-room-0');

      expect(result.isSuccess, true);
      final controller = adapter.getChatController('mock-room-0');
      expect(controller.messages.isNotEmpty, true);
    });

    test('connection state updates flow to adapter notifier', () async {
      adapter.start();

      mockClient.emitEvent(const ChatEvent.connected());
      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.connected,
      );

      mockClient.emitEvent(const ChatEvent.disconnected());
      await Future.delayed(Duration.zero);
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.disconnected,
      );
    });
  });
}
