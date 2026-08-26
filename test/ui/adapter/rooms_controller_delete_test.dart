import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// E-delete — `ChatRoomsController.delete` used to gate ALL persistence
/// (the `clearedAt` cutoff + the never-evictable deleted marker) behind
/// `if (cache != null)`, where `cache` is the ADAPTER's own optional
/// `cache:` constructor arg. WB never passes one (it only wires
/// `ChatConfig.localDatasource`, which feeds the CLIENT's cache), so on WB
/// `delete` was 100% in-memory: the room resurrected with its full history
/// on the next cold start / re-fetch. The fix routes both markers through
/// the client surface (`client.messages.setLocalClearedAt` /
/// `client.rooms.markRoomDeleted`) — the same surface `messages.clearChat`
/// already used — so they persist regardless of the adapter's own cache.
void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    // Deliberately no `cache:` — mirrors WB's exact setup.
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('persists the deleted marker through the client surface even '
      'without an adapter cache', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;

    final result = await adapter.rooms.delete(roomId);
    expect(result.isSuccess, true);

    final deleted = (await client.rooms.getDeletedRoomIds()).dataOrThrow;
    expect(deleted, contains(roomId));
  });

  test('persists the clearedAt cutoff through the client surface even '
      'without an adapter cache', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));

    await adapter.rooms.delete(roomId);

    final clearedAt = (await client.messages.getClearedAt(roomId)).dataOrThrow;
    expect(clearedAt, isNotNull);
    expect(clearedAt!.isAfter(before), true);
  });

  test(
    'marks the room deleted in the in-memory room list immediately',
    () async {
      final created = await client.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Group',
        members: ['u2'],
      );
      final roomId = created.dataOrThrow.id;

      await adapter.rooms.delete(roomId);

      expect(adapter.roomListController.deletedRoomIds, contains(roomId));
    },
  );

  test(
    'end-to-end: a fresh full room-list load excludes the deleted room '
    'even without an adapter cache (was: reappears with full history)',
    () async {
      final created = await client.rooms.create(
        audience: RoomAudience.contacts,
        name: 'Group',
        members: ['u2'],
      );
      final roomId = created.dataOrThrow.id;
      client.addMessage(
        roomId,
        ChatMessage(
          id: 'm1',
          from: 'u2',
          timestamp: DateTime.now().toUtc(),
          text: 'old history',
        ),
      );

      await adapter.rooms.delete(roomId);
      // A fresh adapter/session: the in-memory `RoomListController` markers
      // set by `delete` above are irrelevant here — only what persisted
      // through the client surface matters.
      final freshAdapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
      );
      addTearDown(freshAdapter.dispose);

      final result = await freshAdapter.rooms.load(forceNetwork: true);
      expect(result.isSuccess, true);
      expect(
        freshAdapter.roomListController.allRooms.map((r) => r.id),
        isNot(contains(roomId)),
      );
    },
  );

  test('end-to-end: a peer message after the delete resurrects the room '
      'empty (prior history stays hidden behind clearedAt)', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;
    client.addMessage(
      roomId,
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime.now().toUtc(),
        text: 'old history',
      ),
    );

    await adapter.rooms.delete(roomId);

    // A peer writes again, strictly after the clearedAt cutoff.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    client.addMessage(
      roomId,
      ChatMessage(
        id: 'm2',
        from: 'u2',
        timestamp: DateTime.now().toUtc(),
        text: 'new message',
      ),
    );

    final freshAdapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
    );
    addTearDown(freshAdapter.dispose);

    await freshAdapter.rooms.load(forceNetwork: true);
    expect(
      freshAdapter.roomListController.allRooms.map((r) => r.id),
      contains(roomId),
    );
  });

  group('failing towards "nothing was deleted"', _failOpenGroup);
  group('the mirror is scoped to the session', _sessionScopeGroup);
}

/// The delete marker is the only thing keeping a deleted chat off the room
/// list, so every layer between the store and the room-list build used to
/// answer an unreadable set with the empty set and a failed write with
/// success — both of which read as "this user never deleted anything".
/// QA saw the row come back with its old message and its unread badge on
/// the next background→foreground resync.
void _failOpenGroup() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    // Deliberately no `cache:` — mirrors WB's exact setup.
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Future<String> deletedRoom() async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;
    client.addMessage(
      roomId,
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime.now().toUtc(),
        text: 'old history',
      ),
    );
    await adapter.rooms.delete(roomId);
    return roomId;
  }

  test('a room-list load whose deleted-set read fails keeps the deleted '
      'room off the list (was: it came back with its old message)', () async {
    final roomId = await deletedRoom();
    expect(adapter.roomListController.deletedRoomIds, contains(roomId));

    client.rooms.failDeletedRoomIdsRead = true;
    final result = await adapter.rooms.load(forceNetwork: true);
    expect(result.isSuccess, true);

    expect(
      adapter.roomListController.allRooms.map((r) => r.id),
      isNot(contains(roomId)),
      reason: 'an unreadable marker set is not proof the chat was undeleted',
    );
    expect(adapter.roomListController.deletedRoomIds, contains(roomId));
  });

  test('a legitimate resurrection still un-marks the room even though the '
      'pass no longer replaces the set wholesale', () async {
    final roomId = await deletedRoom();

    await Future<void>.delayed(const Duration(milliseconds: 5));
    client.addMessage(
      roomId,
      ChatMessage(
        id: 'm2',
        from: 'u2',
        timestamp: DateTime.now().toUtc(),
        text: 'new message',
      ),
    );

    await adapter.rooms.load(forceNetwork: true);

    expect(
      adapter.roomListController.allRooms.map((r) => r.id),
      contains(roomId),
    );
    expect(
      adapter.roomListController.deletedRoomIds,
      isNot(contains(roomId)),
    );
  });

  test('delete reports failure and leaves the row on screen when the '
      'durable marker could not be written', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;
    await adapter.rooms.load(forceNetwork: true);
    expect(
      adapter.roomListController.allRooms.map((r) => r.id),
      contains(roomId),
    );

    client.rooms.failMarkRoomDeleted = true;
    final result = await adapter.rooms.delete(roomId);

    expect(
      result.isFailure,
      true,
      reason: 'delete used to return success whatever the store did',
    );
    expect(
      adapter.roomListController.deletedRoomIds,
      isNot(contains(roomId)),
      reason: 'hiding the row without its marker is what makes it come back',
    );
    expect(
      adapter.roomListController.allRooms.map((r) => r.id),
      contains(roomId),
    );
  });

  test('a room-list load whose clear cutoff read fails keeps the cleared row '
      'blank (was: it repainted with its old message and badge)', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;
    client.addMessage(
      roomId,
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime.now().toUtc(),
        text: 'old history',
      ),
    );
    await adapter.messages.clearChat(roomId);

    await adapter.rooms.load(forceNetwork: true);
    expect(
      adapter.roomListController.allRooms
          .firstWhere((r) => r.id == roomId)
          .lastMessage,
      isNull,
    );

    client.messages.failClearedAtRead = true;
    await adapter.rooms.load(forceNetwork: true);

    final row = adapter.roomListController.allRooms.firstWhere(
      (r) => r.id == roomId,
    );
    expect(
      row.lastMessage,
      isNull,
      reason: 'an unreadable cutoff is not proof the chat was never cleared',
    );
    expect(row.unreadCount, 0);
  });

  test('the in-memory mirror only loses ids the caller names', () {
    final controller = adapter.roomListController;
    controller.markDeleted('a');
    controller.markDeleted('b');

    controller.mergeDeletedRoomIds(const {'c'});
    expect(controller.deletedRoomIds, {'a', 'b', 'c'});

    controller.mergeDeletedRoomIds(const {}, remove: const {'b'});
    expect(controller.deletedRoomIds, {'a', 'c'});
  });
}

/// The in-memory deleted mirror is per-user. A room-list pass no longer
/// replaces it wholesale, so the identity swap has to drop it explicitly —
/// otherwise the outgoing user's ids keep hiding rooms for the next one.
void _sessionScopeGroup() {
  test('signOut drops the deleted mirror; disconnect keeps it', () async {
    final client = MockChatClient(currentUserId: 'u1');
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
    );
    addTearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    adapter.roomListController.markDeleted('r-old');

    await adapter.disconnect();
    expect(adapter.roomListController.deletedRoomIds, contains('r-old'));

    await adapter.signOut();
    expect(adapter.roomListController.deletedRoomIds, isEmpty);
  });
}
