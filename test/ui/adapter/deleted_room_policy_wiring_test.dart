import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';

/// The lines that give [DeletedRoomPolicy] its value. The policy has to
/// travel from the public entry point the consumer used down to each of the
/// collaborators that can act on it — the event router, the member event
/// handler and the room enricher — and the enricher additionally has to be
/// able to report its purges back through `onRoomRemoved`. The behaviour
/// tests build those collaborators by hand, so a dropped forward would
/// leave them green and the hook dead for every plug-and-play consumer.
DeletedRoomPolicy _supportPurges(RoomListItem room) =>
    room.custom?['support'] == true
    ? DeletedRoomPolicy.purge
    : DeletedRoomPolicy.keepReadOnly;

const _me = ChatUser(id: 'u1', displayName: 'Me');

const _supportRow = RoomListItem(
  id: 'support1',
  name: 'Support',
  custom: {'support': true},
);

void main() {
  late MockChatClient client;
  late MemoryChatLocalDatasource cache;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    cache = MemoryChatLocalDatasource();
  });

  tearDown(() async => client.dispose());

  test('NomaChat.fromClient hands the policy to the event router', () async {
    final chat = NomaChat.fromClient(
      client: client,
      currentUser: _me,
      cache: cache,
      deletedRoomPolicy: _supportPurges,
    );
    addTearDown(chat.dispose);
    await chat.connect();
    chat.roomListController.addRoom(_supportRow);

    client.emitEvent(const ChatEvent.roomDeleted(roomId: 'support1'));
    await pumpEventQueue();

    expect(chat.roomListController.getRoomById('support1'), isNull);
  });

  test('NomaChat.fromClient hands the policy to the member event '
      'handler', () async {
    final chat = NomaChat.fromClient(
      client: client,
      currentUser: _me,
      cache: cache,
      deletedRoomPolicy: _supportPurges,
    );
    addTearDown(chat.dispose);
    await chat.connect();
    chat.roomListController.addRoom(_supportRow);

    client.emitEvent(
      const ChatEvent.userLeft(
        roomId: 'support1',
        userId: 'u1',
        actorUserId: 'operator',
      ),
    );
    await pumpEventQueue();

    expect(chat.roomListController.getRoomById('support1'), isNull);
  });

  test('the adapter hands the policy AND onRoomRemoved to the room '
      'enricher', () async {
    // The enricher's purge runs on a room-list pass, not on an event, and
    // it disposes the room's chat controller — so the hook that tells the
    // host to pop has to reach it too.
    await cache.markKicked('support1');
    await cache.saveRooms(const [
      ChatRoom(id: 'support1', name: 'Support', custom: {'support': true}),
    ]);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: _me,
      cache: cache,
      deletedRoomPolicy: _supportPurges,
    );
    addTearDown(adapter.dispose);
    final removed = <String>[];
    adapter.onRoomRemoved = (roomId, _, _) => removed.add(roomId);
    client.seedRoom(const ChatRoom(id: 'live1', name: 'Live room'));

    await adapter.rooms.load();
    await pumpEventQueue();

    expect(
      adapter.roomListController.allRooms.map((r) => r.id),
      isNot(contains('support1')),
    );
    expect(removed, ['support1']);
    expect((await cache.getKickedRoomIds()).dataOrThrow, isEmpty);
  });
}
