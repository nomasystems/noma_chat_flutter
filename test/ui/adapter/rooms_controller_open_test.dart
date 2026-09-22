import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

import '../../_helpers/stub_rooms_client.dart';

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  test(
    'a room already in the list is opened without a network fetch',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      mock.seedRoom(
        const ChatRoom(id: 'grp', name: 'Team', members: ['me', 'a']),
      );
      final client = StubRoomsClient(
        mock,
        networkResult: const ChatFailureResult(NotFoundFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      await adapter.rooms.load();
      // `load()` itself fetches per-room detail as part of its own bulk
      // enrichment — that's unrelated to `open()`. What matters is that
      // `open()` doesn't issue any ADDITIONAL `get()` call once the room is
      // already known to the list.
      final networkReadsAfterLoad = client.rooms.networkReads;

      final result = await adapter.rooms.open('grp');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.roomId, 'grp');
      expect(client.rooms.networkReads, networkReadsAfterLoad);
    },
  );

  test(
    'a room missing from the list is fetched from the server and added',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = StubRoomsClient(
        mock,
        networkResult: const ChatSuccess(
          RoomDetail(
            id: 'new-room',
            name: 'Fresh',
            type: RoomType.group,
            memberCount: 2,
            userRole: RoomRole.member,
            config: RoomConfig(allowInvitations: false),
          ),
        ),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('new-room');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.roomId, 'new-room');
      expect(client.rooms.networkReads, 1);
      expect(adapter.roomListController.getRoomById('new-room'), isNotNull);
      expect(adapter.roomListController.getRoomById('new-room')?.name, 'Fresh');
    },
  );

  test(
    'fetchIfMissing: false returns NotFoundFailure without hitting the network',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      final client = StubRoomsClient(
        mock,
        networkResult: const ChatFailureResult(NotFoundFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('missing', fetchIfMissing: false);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
      expect(client.rooms.networkReads, 0);
    },
  );

  test('a room the server reports gone maps to NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = StubRoomsClient(
      mock,
      networkResult: const ChatFailureResult(NotFoundFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('gone');

    expect(result.failureOrNull, isA<NotFoundFailure>());
  });

  test('an auth problem maps to AuthFailure, not NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = StubRoomsClient(
      mock,
      networkResult: const ChatFailureResult(AuthFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<AuthFailure>());
  });

  test(
    'a permission problem maps to ForbiddenFailure, not NotFoundFailure',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = StubRoomsClient(
        mock,
        networkResult: const ChatFailureResult(
          ForbiddenFailure(statusCode: 403),
        ),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('some-room');

      expect(result.failureOrNull, isA<ForbiddenFailure>());
    },
  );

  test('the REST layer reporting a NetworkFailure (client otherwise connected) '
      'still propagates as NetworkFailure, not NotFoundFailure', () async {
    final mock = MockChatClient(currentUserId: 'me');
    await mock.connect();
    final client = StubRoomsClient(
      mock,
      networkResult: const ChatFailureResult(NetworkFailure()),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(client.rooms.networkReads, 1);
  });

  test('a client that already knows it is offline (disconnected) fast-fails '
      'without a network round-trip (R2-17)', () async {
    final mock = MockChatClient(currentUserId: 'me');
    // Deliberately NOT connected — MockChatClient defaults to
    // ChatConnectionState.disconnected, mirroring a cold app launch with
    // no network before the first `connect()` succeeds.
    final client = StubRoomsClient(
      mock,
      networkResult: const ChatSuccess(
        RoomDetail(
          id: 'some-room',
          name: 'Should never be reached',
          type: RoomType.group,
          memberCount: 2,
          userRole: RoomRole.member,
          config: RoomConfig(allowInvitations: false),
        ),
      ),
    );
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);

    final result = await adapter.rooms.open('some-room');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(
      client.rooms.networkReads,
      0,
      reason:
          'a known-offline client must fast-fail before ever '
          'attempting the network round-trip',
    );
  });

  test(
    'a network timeout maps to TimeoutFailure, not NotFoundFailure',
    () async {
      final mock = MockChatClient(currentUserId: 'me');
      await mock.connect();
      final client = StubRoomsClient(
        mock,
        networkResult: const ChatFailureResult(TimeoutFailure()),
      );
      final adapter = ChatUiAdapter(client: client, currentUser: me);
      addTearDown(adapter.dispose);

      final result = await adapter.rooms.open('some-room');

      expect(result.failureOrNull, isA<TimeoutFailure>());
    },
  );
}
