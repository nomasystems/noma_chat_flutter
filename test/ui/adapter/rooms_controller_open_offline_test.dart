import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

import '../../_helpers/stub_rooms_client.dart';

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const onDisk = RoomDetail(
    id: 'cached-room',
    name: 'Known offline',
    type: RoomType.group,
    memberCount: 3,
    userRole: RoomRole.member,
    config: RoomConfig(allowInvitations: false),
  );

  test('a disconnected client opens a room it already has on disk, without '
      'a network round-trip', () async {
    final mock = MockChatClient(currentUserId: 'me');
    // Deliberately NOT connected: the push-opened-offline case.
    final client = StubRoomsClient(
      mock,
      cachedResult: const ChatSuccess(onDisk),
      networkResult: const ChatFailureResult(NotFoundFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('cached-room');

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.roomId, 'cached-room');
    expect(client.rooms.cacheReads, 1);
    expect(
      client.rooms.networkReads,
      0,
      reason: 'a room read from disk must not cost a request',
    );
    expect(
      adapter.roomListController.getRoomById('cached-room')?.name,
      'Known offline',
    );
  });

  test('a disconnected client with nothing on disk still fast-fails with the '
      'offline NetworkFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    final client = StubRoomsClient(
      mock,
      networkResult: const ChatSuccess(onDisk),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('cached-room');

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(result.failureOrNull?.message, 'Offline: room not fetched');
    expect(client.rooms.cacheReads, 1);
    expect(client.rooms.networkReads, 0);
    expect(adapter.roomListController.getRoomById('cached-room'), isNull);
  });

  test('a connected client ignores the disk copy and asks the server, so a '
      'room the user was removed from stays gone', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = StubRoomsClient(
      mock,
      cachedResult: const ChatSuccess(onDisk),
      networkResult: const ChatFailureResult(ForbiddenFailure(statusCode: 403)),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('cached-room');

    expect(result.failureOrNull, isA<ForbiddenFailure>());
    expect(
      client.rooms.cacheReads,
      0,
      reason: 'a stale disk copy must never answer for a reachable server',
    );
    expect(client.rooms.networkReads, 1);
    expect(adapter.roomListController.getRoomById('cached-room'), isNull);
  });

  test('a connected client fetches a room absent from the list even with a '
      'copy on disk', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = StubRoomsClient(
      mock,
      cachedResult: const ChatSuccess(onDisk),
      networkResult: const ChatSuccess(
        RoomDetail(
          id: 'cached-room',
          name: 'Renamed on the server',
          type: RoomType.group,
          memberCount: 4,
          userRole: RoomRole.member,
          config: RoomConfig(allowInvitations: false),
        ),
      ),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('cached-room');

    expect(result.isSuccess, isTrue);
    expect(client.rooms.cacheReads, 0);
    expect(client.rooms.networkReads, 1);
    expect(
      adapter.roomListController.getRoomById('cached-room')?.name,
      'Renamed on the server',
    );
  });
}
