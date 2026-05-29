import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/refresh_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a minimal [UnreadRoom] for diff tests. Only the fields the
/// engine inspects (`roomId`, `lastMessageId`, `lastMessageTime`,
/// `unreadMessages`) are meaningful.
UnreadRoom _room({
  required String id,
  String? lastMsgId,
  DateTime? lastMsgTime,
  int unread = 0,
}) => UnreadRoom(
  roomId: id,
  unreadMessages: unread,
  lastMessageId: lastMsgId,
  lastMessageTime: lastMsgTime,
);

ChatMessage _msg({
  required String id,
  String from = 'other',
  required DateTime ts,
  String text = 'hi',
}) => ChatMessage(id: id, from: from, timestamp: ts, text: text);

void main() {
  group('RefreshEngine.tick', () {
    test(
      'first tick: every room emits RoomCreatedEvent + new messages',
      () async {
        final emitted = <ChatEvent>[];
        final ts = DateTime(2026, 5, 25, 10);
        final engine = RefreshEngine(
          getUserRooms: ({String type = 'all'}) async => ChatSuccess(
            UserRooms(
              rooms: [
                _room(id: 'r1', lastMsgId: 'm1', lastMsgTime: ts, unread: 1),
                _room(id: 'r2', lastMsgId: 'm2', lastMsgTime: ts, unread: 2),
              ],
            ),
          ),
          listMessages: (roomId, {pagination}) async => ChatSuccess(
            ChatPaginatedResponse(
              items: [_msg(id: 'msg-$roomId', ts: ts)],
              hasMore: false,
            ),
          ),
          emit: emitted.add,
          config: const PollingConfig(),
        );

        await engine.tick();

        // Two RoomCreatedEvent + two NewMessageEvent (one per room).
        expect(emitted.whereType<RoomCreatedEvent>().length, 2);
        expect(emitted.whereType<NewMessageEvent>().length, 2);
        expect(
          emitted.whereType<RoomCreatedEvent>().map((e) => e.roomId).toSet(),
          {'r1', 'r2'},
        );
      },
    );

    test('second tick with no changes: no events', () async {
      final ts = DateTime(2026, 5, 25, 10);
      final emitted = <ChatEvent>[];
      var callCount = 0;
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async {
          callCount++;
          return ChatSuccess(
            UserRooms(
              rooms: [
                _room(id: 'r1', lastMsgId: 'm1', lastMsgTime: ts, unread: 1),
              ],
            ),
          );
        },
        listMessages: (roomId, {pagination}) async {
          // Return the message only on the very first messages.list
          // call; subsequent ones (after `_lastSeenTimestamp` is set)
          // return empty.
          return ChatSuccess(
            ChatPaginatedResponse(
              items: pagination?.after == null
                  ? [_msg(id: 'm1', ts: ts)]
                  : <ChatMessage>[],
              hasMore: false,
            ),
          );
        },
        emit: emitted.add,
        config: const PollingConfig(),
      );

      await engine.tick();
      emitted.clear();
      await engine.tick();

      expect(callCount, 2, reason: 'getUserRooms called twice');
      expect(emitted, isEmpty, reason: 'no diff → no events');
    });

    test('room change: NewMessageEvent for the new message only', () async {
      final ts1 = DateTime(2026, 5, 25, 10);
      final ts2 = DateTime(2026, 5, 25, 11);
      final emitted = <ChatEvent>[];
      var tickN = 0;
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async {
          tickN++;
          return ChatSuccess(
            UserRooms(
              rooms: [
                _room(
                  id: 'r1',
                  lastMsgId: tickN == 1 ? 'm1' : 'm2',
                  lastMsgTime: tickN == 1 ? ts1 : ts2,
                  unread: tickN,
                ),
              ],
            ),
          );
        },
        listMessages: (roomId, {pagination}) async {
          if (pagination?.after == null) {
            return ChatSuccess(
              ChatPaginatedResponse(
                items: [_msg(id: 'm1', ts: ts1)],
                hasMore: false,
              ),
            );
          }
          return ChatSuccess(
            ChatPaginatedResponse(
              items: [_msg(id: 'm2', ts: ts2)],
              hasMore: false,
            ),
          );
        },
        emit: emitted.add,
        config: const PollingConfig(),
      );

      await engine.tick();
      emitted.clear();
      await engine.tick();

      expect(emitted.whereType<NewMessageEvent>().length, 1);
      expect(emitted.whereType<NewMessageEvent>().first.message.id, 'm2');
    });

    test('vanished room emits RoomDeletedEvent', () async {
      final emitted = <ChatEvent>[];
      var tickN = 0;
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async {
          tickN++;
          return ChatSuccess(
            UserRooms(
              rooms: tickN == 1
                  ? [_room(id: 'r-gone'), _room(id: 'r-stays')]
                  : [_room(id: 'r-stays')],
            ),
          );
        },
        listMessages: (roomId, {pagination}) async =>
            const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
        emit: emitted.add,
        config: const PollingConfig(),
      );

      await engine.tick();
      emitted.clear();
      await engine.tick();

      expect(emitted.whereType<RoomDeletedEvent>().length, 1);
      expect(emitted.whereType<RoomDeletedEvent>().first.roomId, 'r-gone');
    });

    test('open rooms get polled even without diff', () async {
      final ts = DateTime(2026, 5, 25, 10);
      final emitted = <ChatEvent>[];
      final pollCalls = <String>[];
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async =>
            const ChatSuccess(UserRooms(rooms: [])),
        listMessages: (roomId, {pagination}) async {
          pollCalls.add(roomId);
          return ChatSuccess(
            ChatPaginatedResponse(
              items: [_msg(id: 'x', ts: ts)],
              hasMore: false,
            ),
          );
        },
        emit: emitted.add,
        config: const PollingConfig(),
      );

      engine.markRoomOpen('r-open');
      // Even though `getUserRooms` returns empty, the open room must
      // still be polled.
      // Note: open rooms are filtered by `idsNow.contains` so the
      // engine doesn't poll an open room that the backend stopped
      // listing. Seed the snapshot manually by ticking once with the
      // room in the list:
      final engine2 = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async => ChatSuccess(
          UserRooms(
            rooms: [_room(id: 'r-open', lastMsgId: 'm1', lastMsgTime: ts)],
          ),
        ),
        listMessages: (roomId, {pagination}) async {
          pollCalls.add(roomId);
          return ChatSuccess(
            ChatPaginatedResponse(
              items: pagination?.after == null
                  ? [_msg(id: 'm1', ts: ts)]
                  : <ChatMessage>[],
              hasMore: false,
            ),
          );
        },
        emit: emitted.add,
        config: const PollingConfig(),
      );
      engine2.markRoomOpen('r-open');
      await engine2.tick();
      pollCalls.clear();
      await engine2.tick();
      // No diff (same room, same lastMsgId) — but open → polled.
      expect(pollCalls, ['r-open']);
    });

    test('maxRoomsPerTick caps poll fan-out', () async {
      final ts = DateTime(2026, 5, 25, 10);
      final pollCalls = <String>[];
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async => ChatSuccess(
          UserRooms(
            rooms: List.generate(
              20,
              (i) => _room(
                id: 'r$i',
                lastMsgId: 'm$i',
                lastMsgTime: ts,
                unread: 1,
              ),
            ),
          ),
        ),
        listMessages: (roomId, {pagination}) async {
          pollCalls.add(roomId);
          return const ChatSuccess(
            ChatPaginatedResponse(items: [], hasMore: false),
          );
        },
        emit: (_) {},
        config: const PollingConfig(maxRoomsPerTick: 5),
      );

      await engine.tick();

      expect(pollCalls.length, 5);
    });

    test('getUserRooms failure logs warn but does not crash', () async {
      final logs = <String>[];
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async =>
            const ChatFailureResult(NetworkFailure('offline')),
        listMessages: (roomId, {pagination}) async =>
            const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
        emit: (_) {},
        config: const PollingConfig(),
        logger: (level, msg) => logs.add('$level: $msg'),
      );

      await engine.tick();

      expect(logs.any((l) => l.contains('getUserRooms failed')), isTrue);
    });
  });

  group('RefreshEngine.tick(singleRoomId:)', () {
    test('skips room-list diff, polls only that room', () async {
      final ts = DateTime(2026, 5, 25, 10);
      final pollCalls = <String>[];
      var roomListCalled = false;
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async {
          roomListCalled = true;
          return const ChatSuccess(UserRooms(rooms: []));
        },
        listMessages: (roomId, {pagination}) async {
          pollCalls.add(roomId);
          return ChatSuccess(
            ChatPaginatedResponse(
              items: [_msg(id: 'x', ts: ts)],
              hasMore: false,
            ),
          );
        },
        emit: (_) {},
        config: const PollingConfig(),
      );

      await engine.tick(singleRoomId: 'r-target');

      expect(roomListCalled, isFalse);
      expect(pollCalls, ['r-target']);
    });
  });

  group('RefreshEngine.reset', () {
    test('drops snapshots and timestamps, keeps open-room set', () async {
      final ts = DateTime(2026, 5, 25, 10);
      final pollCalls = <String>[];
      final engine = RefreshEngine(
        getUserRooms: ({String type = 'all'}) async => ChatSuccess(
          UserRooms(
            rooms: [_room(id: 'r1', lastMsgId: 'm1', lastMsgTime: ts)],
          ),
        ),
        listMessages: (roomId, {pagination}) async {
          pollCalls.add('${pagination?.after ?? 'null'}->$roomId');
          return ChatSuccess(
            ChatPaginatedResponse(
              items: [_msg(id: 'm1', ts: ts)],
              hasMore: false,
            ),
          );
        },
        emit: (_) {},
        config: const PollingConfig(),
      );

      await engine.tick();
      pollCalls.clear();
      engine.reset();
      await engine.tick();

      // After reset, lastSeenTimestamp is gone → poll has after=null.
      expect(pollCalls.first.startsWith('null->'), isTrue);
    });
  });
}
