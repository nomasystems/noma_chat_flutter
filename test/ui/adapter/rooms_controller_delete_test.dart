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

  test('marks the room deleted in the in-memory room list immediately', () async {
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      name: 'Group',
      members: ['u2'],
    );
    final roomId = created.dataOrThrow.id;

    await adapter.rooms.delete(roomId);

    expect(adapter.roomListController.deletedRoomIds, contains(roomId));
  });

  test('end-to-end: a fresh full room-list load excludes the deleted room '
      'even without an adapter cache (was: reappears with full history)', () async {
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
    final freshAdapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(freshAdapter.dispose);

    final result = await freshAdapter.rooms.load(forceNetwork: true);
    expect(result.isSuccess, true);
    expect(
      freshAdapter.roomListController.allRooms.map((r) => r.id),
      isNot(contains(roomId)),
    );
  });

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

    final freshAdapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(freshAdapter.dispose);

    await freshAdapter.rooms.load(forceNetwork: true);
    expect(
      freshAdapter.roomListController.allRooms.map((r) => r.id),
      contains(roomId),
    );
  });
}
