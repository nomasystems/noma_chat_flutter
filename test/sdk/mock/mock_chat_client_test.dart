import 'package:noma_chat/noma_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockChatClient', () {
    late MockChatClient client;

    setUp(() {
      client = MockChatClient(currentUserId: 'test-user');
    });

    tearDown(() => client.dispose());

    test('starts disconnected', () {
      expect(client.connectionState, ChatConnectionState.disconnected);
    });

    test('connect emits connected event', () async {
      final events = <ChatEvent>[];
      client.events.listen(events.add);
      await client.connect();
      expect(client.connectionState, ChatConnectionState.connected);
      expect(events, contains(isA<ConnectedEvent>()));
    });

    test('disconnect emits disconnected event', () async {
      await client.connect();
      final events = <ChatEvent>[];
      client.events.listen(events.add);
      await client.disconnect();
      expect(client.connectionState, ChatConnectionState.disconnected);
      expect(events, contains(isA<DisconnectedEvent>()));
    });

    test('health check returns ok', () async {
      final result = await client.auth.healthCheck();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.isHealthy, isTrue);
    });

    test('get current user returns mock user', () async {
      final result = await client.users.get('test-user');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.id, 'test-user');
      expect(result.dataOrNull?.displayName, 'Mock User');
    });

    test('get unknown user returns NotFoundFailure', () async {
      final result = await client.users.get('unknown');
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('create room and list rooms', () async {
      await client.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Test Room',
      );
      final result = await client.rooms.getUserRooms();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.rooms.length, 1);
    });

    test('send message and list messages', () async {
      final createResult = await client.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Chat Room',
      );
      final roomId = createResult.dataOrNull!.id;

      final sendResult = await client.messages.send(roomId, text: 'Hello!');
      expect(sendResult.isSuccess, isTrue);
      expect(sendResult.dataOrNull?.text, 'Hello!');
      expect(sendResult.dataOrNull?.from, 'test-user');

      final listResult = await client.messages.list(roomId);
      expect(listResult.isSuccess, isTrue);
      expect(listResult.dataOrNull?.items.length, 1);
    });

    test('send message emits newMessage event', () async {
      final createResult = await client.rooms.create(
        audience: RoomAudience.contacts,
      );
      final roomId = createResult.dataOrNull!.id;

      final events = <ChatEvent>[];
      client.events.listen(events.add);

      await client.messages.send(roomId, text: 'Hello!');
      expect(events, contains(isA<NewMessageEvent>()));
    });

    test('add and list contacts', () async {
      await client.contacts.add('friend-1');
      final result = await client.contacts.list();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.items.length, 1);
      expect(result.dataOrNull?.items.first.userId, 'friend-1');
    });

    test('presence returns available', () async {
      final result = await client.presence.getOwn();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.status, PresenceStatus.available);
      expect(result.dataOrNull?.online, isTrue);
    });

    test('search users by displayName', () async {
      final result = await client.users.search('Mock');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.items.length, 1);
    });

    test('search users with no match', () async {
      final result = await client.users.search('nonexistent');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.items, isEmpty);
    });

    test('list members of room', () async {
      final createResult = await client.rooms.create(
        audience: RoomAudience.contacts,
        members: ['user-2'],
      );
      final roomId = createResult.dataOrNull!.id;
      final result = await client.members.list(roomId);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.items.length, 2);
    });

    test('list members of nonexistent room', () async {
      final result = await client.members.list('nonexistent');
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('search messages accepts CursorPaginationParams', () async {
      final createResult = await client.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Search Room',
      );
      final roomId = createResult.dataOrNull!.id;
      await client.messages.send(roomId, text: 'findme');

      final result = await client.messages.search(
        'findme',
        roomId: roomId,
        pagination: const PaginationParams(limit: 10),
      );
      expect(result.isSuccess, isTrue);
    });
  });
}
