import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';

class _MockPresenceApi extends Mock implements ChatPresenceApi {}

void main() {
  group('PresenceRegistry', () {
    late _MockPresenceApi api;
    late RoomListController roomList;
    late DmContactRegistry dmContacts;

    setUp(() {
      api = _MockPresenceApi();
      roomList = RoomListController();
      dmContacts = DmContactRegistry();
    });

    tearDown(() => roomList.dispose());

    PresenceRegistry make({bool isDisposed = false}) => PresenceRegistry(
      api: api,
      roomList: roomList,
      dmContacts: dmContacts,
      isDisposed: () => isDisposed,
    );

    test('presenceFor returns null when no event has landed', () {
      expect(make().presenceFor('u1'), isNull);
    });

    test('update caches the presence', () {
      final pm = make();
      pm.update('u1', true, PresenceStatus.available);
      expect(pm.presenceFor('u1')?.online, isTrue);
      expect(pm.presenceFor('u1')?.status, PresenceStatus.available);
    });

    test('update propagates to the matching DM RoomListItem', () {
      const room = RoomListItem(id: 'r1', otherUserId: 'u1');
      roomList.addRoom(room);
      dmContacts.bind('u1', 'r1');

      final pm = make();
      pm.update('u1', true, PresenceStatus.busy);

      final updated = roomList.getRoomById('r1')!;
      expect(updated.isOnline, isTrue);
      expect(updated.presenceStatus, PresenceStatus.busy);
    });

    test('update is a no-op when no DM is registered for the user', () {
      final pm = make();
      pm.update('u1', true, PresenceStatus.available);
      // No room → no-op (and no throw).
      expect(roomList.allRooms, isEmpty);
    });

    test('update skips group rooms even when contact is bound', () {
      const room = RoomListItem(id: 'r1', otherUserId: 'u1', isGroup: true);
      roomList.addRoom(room);
      dmContacts.bind('u1', 'r1');

      final pm = make();
      pm.update('u1', true, PresenceStatus.available);

      final unchanged = roomList.getRoomById('r1')!;
      // RoomListItem.isOnline default is null — group rooms never carry presence.
      expect(unchanged.isOnline, isNull);
    });

    test('bootstrap populates cache + reflects in matching DM rooms', () async {
      const room = RoomListItem(id: 'r1', otherUserId: 'u1');
      roomList.addRoom(room);

      when(() => api.getAll()).thenAnswer(
        (_) async => const ChatSuccess(
          BulkPresenceResponse(
            own: ChatPresence(
              userId: 'me',
              online: true,
              status: PresenceStatus.available,
            ),
            contacts: [
              ChatPresence(
                userId: 'u1',
                online: true,
                status: PresenceStatus.available,
              ),
            ],
          ),
        ),
      );

      await make().bootstrap();
      expect(roomList.getRoomById('r1')!.isOnline, isTrue);
    });

    test('bootstrap is silent on API failure (logged, swallowed)', () async {
      final sink = BufferChatLogSink();
      when(
        () => api.getAll(),
      ).thenAnswer((_) async => const ChatFailureResult(NetworkFailure()));

      final pm = PresenceRegistry(
        api: api,
        roomList: roomList,
        dmContacts: dmContacts,
        isDisposed: () => false,
        logs: ChatLogger(sink: sink),
      );
      await pm.bootstrap();
      // ChatFailureResult path doesn't log warn because the ChatResult is checked
      // explicitly (dataOrNull == null branch). The "log + swallow"
      // catch is for THROWN exceptions, not ChatFailureResult results — the
      // semantics match the original adapter behaviour.
      expect(pm.length, 0);
    });

    test('bootstrap short-circuits when isDisposed flips mid-flight', () async {
      const room = RoomListItem(id: 'r1', otherUserId: 'u1');
      roomList.addRoom(room);

      var disposed = false;
      when(() => api.getAll()).thenAnswer((_) async {
        disposed = true; // simulate dispose racing the await
        return const ChatSuccess(
          BulkPresenceResponse(
            own: ChatPresence(
              userId: 'me',
              online: true,
              status: PresenceStatus.available,
            ),
            contacts: [
              ChatPresence(
                userId: 'u1',
                online: true,
                status: PresenceStatus.available,
              ),
            ],
          ),
        );
      });

      final pm = PresenceRegistry(
        api: api,
        roomList: roomList,
        dmContacts: dmContacts,
        isDisposed: () => disposed,
      );
      await pm.bootstrap();
      // dispose was true on return → cache untouched, room untouched.
      expect(pm.length, 0);
      expect(roomList.getRoomById('r1')!.isOnline, isNull);
    });

    test('clear empties the cache', () {
      final pm = make();
      pm.update('u1', true, PresenceStatus.available);
      pm.update('u2', false, PresenceStatus.offline);
      expect(pm.length, 2);
      pm.clear();
      expect(pm.length, 0);
    });

    test('bootstrap leaves group rooms untouched even when contact id '
        'matches a member', () async {
      // Group rooms must never carry the cosmetic isOnline/presenceStatus
      // fields — they reflect DM peer state only. The bootstrap iterates
      // `roomList.allRooms` and SHOULD skip groups via `room.isGroup`.
      const group = RoomListItem(id: 'g1', otherUserId: 'u1', isGroup: true);
      roomList.addRoom(group);

      when(() => api.getAll()).thenAnswer(
        (_) async => const ChatSuccess(
          BulkPresenceResponse(
            own: ChatPresence(
              userId: 'me',
              online: true,
              status: PresenceStatus.available,
            ),
            contacts: [
              ChatPresence(
                userId: 'u1',
                online: true,
                status: PresenceStatus.available,
              ),
            ],
          ),
        ),
      );

      await make().bootstrap();

      final unchanged = roomList.getRoomById('g1')!;
      expect(unchanged.isOnline, isNull);
      expect(unchanged.presenceStatus, isNull);
    });

    test('bootstrap caches contacts even when no DM room is currently '
        'in the list — late binding sees the cached value via update', () {
      // Scenario: presence_changed event arrives for `u1`, then later
      // `_resolveDmContact` adds the DM room with `otherUserId == u1`.
      // The room widget should reflect the cached presence when the
      // adapter syncs them via update() (e.g. from the enricher).
      final pm = make();
      pm.update('u1', true, PresenceStatus.away);

      // Now the DM room shows up + gets bound.
      const room = RoomListItem(id: 'r1', otherUserId: 'u1');
      roomList.addRoom(room);
      dmContacts.bind('u1', 'r1');

      // Re-applying update with the cached value reflects in the room.
      final cached = pm.presenceFor('u1');
      expect(cached, isNotNull);
      pm.update('u1', cached!.online, cached.status);

      final updated = roomList.getRoomById('r1')!;
      expect(updated.isOnline, isTrue);
      expect(updated.presenceStatus, PresenceStatus.away);
    });

    test(
      'bootstrap does not clobber a live presence event that landed during '
      'its in-flight getAll() — last-writer by recency, not arrival (R2-13)',
      () async {
        const room = RoomListItem(id: 'r1', otherUserId: 'u1');
        roomList.addRoom(room);
        dmContacts.bind('u1', 'r1');
        final pm = make();

        // Hold the snapshot fetch open, and have it resolve to a STALE view
        // (u1 offline) — the state as of when the connection came up.
        final gate = Completer<void>();
        when(() => api.getAll()).thenAnswer((_) async {
          await gate.future;
          return const ChatSuccess(
            BulkPresenceResponse(
              own: ChatPresence(
                userId: 'me',
                online: true,
                status: PresenceStatus.available,
              ),
              contacts: [
                ChatPresence(
                  userId: 'u1',
                  online: false,
                  status: PresenceStatus.offline,
                ),
              ],
            ),
          );
        });

        final f = pm.bootstrap();
        // Let a little wall-clock time pass so the live update below is
        // unambiguously stamped after bootstrap captured its start instant.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // A fresh live event lands WHILE the fetch is still open: u1 online.
        pm.update('u1', true, PresenceStatus.available);
        gate.complete();
        await f;

        // The live (fresher) online state must win over the stale snapshot.
        expect(pm.presenceFor('u1')?.online, isTrue);
        expect(roomList.getRoomById('r1')!.isOnline, isTrue);
      },
    );

    test('bootstrap is reentrant — calling twice does not duplicate '
        'cache entries', () async {
      when(() => api.getAll()).thenAnswer(
        (_) async => const ChatSuccess(
          BulkPresenceResponse(
            own: ChatPresence(
              userId: 'me',
              online: true,
              status: PresenceStatus.available,
            ),
            contacts: [
              ChatPresence(
                userId: 'u1',
                online: true,
                status: PresenceStatus.available,
              ),
              ChatPresence(
                userId: 'u2',
                online: false,
                status: PresenceStatus.offline,
              ),
            ],
          ),
        ),
      );

      final pm = make();
      await pm.bootstrap();
      await pm.bootstrap();
      // Each contact appears once in the cache regardless of bootstrap count.
      expect(pm.length, 2);
    });

    test(
      'bootstrap applies every changed DM room in a single batch instead of '
      'one RoomListController rebuild per room',
      () async {
        for (var i = 0; i < 5; i++) {
          roomList.addRoom(RoomListItem(id: 'r$i', otherUserId: 'u$i'));
        }

        when(() => api.getAll()).thenAnswer(
          (_) async => ChatSuccess(
            BulkPresenceResponse(
              own: const ChatPresence(
                userId: 'me',
                online: true,
                status: PresenceStatus.available,
              ),
              contacts: [
                for (var i = 0; i < 5; i++)
                  ChatPresence(
                    userId: 'u$i',
                    online: true,
                    status: PresenceStatus.available,
                  ),
              ],
            ),
          ),
        );

        var notifyCount = 0;
        roomList.addListener(() => notifyCount++);

        await make().bootstrap();

        // All 5 DM rooms flipped isOnline in one go — a single
        // mergeRooms(authoritative: false) call — not 5 separate
        // updateRoom calls (which would each sort + reindex + notify).
        expect(notifyCount, 1);
        for (var i = 0; i < 5; i++) {
          expect(roomList.getRoomById('r$i')!.isOnline, isTrue);
        }
      },
    );

    test(
      'bootstrap does not notify listeners when no room actually changed',
      () async {
        const room = RoomListItem(
          id: 'r1',
          otherUserId: 'u1',
          isOnline: true,
          presenceStatus: PresenceStatus.available,
        );
        roomList.addRoom(room);

        when(() => api.getAll()).thenAnswer(
          (_) async => const ChatSuccess(
            BulkPresenceResponse(
              own: ChatPresence(
                userId: 'me',
                online: true,
                status: PresenceStatus.available,
              ),
              contacts: [
                ChatPresence(
                  userId: 'u1',
                  online: true,
                  status: PresenceStatus.available,
                ),
              ],
            ),
          ),
        );

        var notifyCount = 0;
        roomList.addListener(() => notifyCount++);

        await make().bootstrap();

        expect(notifyCount, 0);
      },
    );
  });
}
