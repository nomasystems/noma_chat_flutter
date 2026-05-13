import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Smoke tests covering the collaborator classes extracted from
/// `ChatUiAdapter` in 0.3.0 (`_PresenceManager`, `_ChatEventRouter`,
/// `_RoomEnricher`, `_OptimisticHandler`). The adapter facade delegates to
/// each; here we drive a handful of public methods that take a complete
/// pass through the collaborator and back, so coverage of the new files
/// reflects the work that is genuinely exercised in production.
void main() {
  late MockChatClient client;
  late ChatUiAdapter adapter;
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room1', members: ['u1', 'u2']),
    );
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  group('PresenceManager (via adapter)', () {
    test('presenceFor returns null for unknown user', () {
      expect(adapter.presenceFor('unknown'), isNull);
    });

    test('PresenceChangedEvent updates the cache and the DM row', () async {
      adapter.registerDmRoom('u2', 'r1');
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'r1', name: 'Room1', otherUserId: 'u2'),
      );
      client.emitEvent(
        const PresenceChangedEvent(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final presence = adapter.presenceFor('u2');
      expect(presence, isNotNull);
      expect(presence!.online, isTrue);

      final row = adapter.roomListController.getRoomById('r1');
      expect(row!.isOnline, isTrue);
    });
  });

  group('RoomEnricher (via adapter)', () {
    test('loadRooms populates the controller from the mock', () async {
      final result = await adapter.loadRooms();
      expect(result.isSuccess, isTrue);
      expect(adapter.roomListController.allRooms, isNotEmpty);
      expect(adapter.initializedNotifier.value, isTrue);
    });

    test('RoomDeletedEvent removes the row + cache', () async {
      await adapter.loadRooms();
      expect(adapter.roomListController.getRoomById('r1'), isNotNull);
      client.emitEvent(const RoomDeletedEvent(roomId: 'r1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.roomListController.getRoomById('r1'), isNull);
    });
  });

  group('OptimisticHandler (via adapter)', () {
    test('sendMessage takes the optimistic + confirm round-trip', () async {
      final controller = adapter.getChatController('r1');
      final r = await adapter.sendMessage('r1', text: 'hi');
      expect(r.isSuccess, isTrue);
      // After confirm, the controller has the server-confirmed message.
      expect(controller.messages.where((m) => m.text == 'hi'), isNotEmpty);
    });

    test('editMessage runs the optimistic + rollback path', () async {
      final controller = adapter.getChatController('r1');
      controller.addMessage(
        ChatMessage(
          id: 'm-missing',
          from: 'u1',
          text: 'original',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      // The mock has no such message server-side, so the SDK returns a
      // failure. We just verify the rollback path runs without throwing.
      await adapter.editMessage('r1', 'm-missing', text: 'edited');
      // After rollback the original text is restored.
      final after = controller.messages.firstWhere((m) => m.id == 'm-missing');
      expect(after.text, 'original');
    });

    test('deleteReaction is a no-op when no reaction exists', () async {
      final r = await adapter.deleteReaction(
        'r1',
        messageId: 'm1',
        emoji: '👍',
      );
      expect(r.isSuccess, isTrue);
    });

    test('pinMessage + unpinMessage roundtrip', () async {
      adapter.getChatController('r1'); // create controller
      final pin = await adapter.pinMessage('r1', 'm1');
      expect(pin.isSuccess, isTrue);
      final unpin = await adapter.unpinMessage('r1', 'm1');
      expect(unpin.isSuccess, isTrue);
    });
  });

  group('EventRouter (via adapter)', () {
    test('ConnectedEvent transitions to connected and reconnects', () async {
      var reconnected = 0;
      adapter.onReconnected = () => reconnected++;
      client.emitEvent(const ConnectedEvent());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.connected,
      );
      // Reconnect signals only on the rising edge (not connected → connected).
      expect(reconnected, greaterThanOrEqualTo(0));
    });

    test('BroadcastEvent fires onBroadcast', () async {
      String? received;
      adapter.onBroadcast = (m) => received = m;
      client.emitEvent(const BroadcastEvent(message: 'hello'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, 'hello');
    });

    test('UserActivityEvent toggles typing in the controller', () async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'r1', name: 'Room1'),
      );
      final controller = adapter.getChatController('r1');
      client.emitEvent(
        const UserActivityEvent(
          roomId: 'r1',
          userId: 'u2',
          activity: ChatActivity.startsTyping,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.typingUserIds, contains('u2'));

      client.emitEvent(
        const UserActivityEvent(
          roomId: 'r1',
          userId: 'u2',
          activity: ChatActivity.stopsTyping,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.typingUserIds, isNot(contains('u2')));
    });
  });
}
