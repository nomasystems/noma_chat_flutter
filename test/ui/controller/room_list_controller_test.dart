import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late RoomListController controller;

  RoomListItem makeRoom(
    String id, {
    DateTime? lastMessageTime,
    bool pinned = false,
    String? name,
    int unreadCount = 0,
  }) => RoomListItem(
    id: id,
    name: name ?? 'Room $id',
    lastMessageTime: lastMessageTime ?? DateTime(2026, 1, 1),
    pinned: pinned,
    unreadCount: unreadCount,
  );

  setUp(() {
    controller = RoomListController(
      initialRooms: [
        makeRoom('1', lastMessageTime: DateTime(2026, 1, 1)),
        makeRoom('2', lastMessageTime: DateTime(2026, 1, 3)),
        makeRoom('3', lastMessageTime: DateTime(2026, 1, 2)),
      ],
    );
  });

  group('sorting', () {
    test('rooms are sorted by lastMessageTime descending', () {
      expect(controller.rooms.map((r) => r.id).toList(), ['2', '3', '1']);
    });

    test('pinned rooms come first', () {
      controller.setRooms([
        makeRoom('a', lastMessageTime: DateTime(2026, 1, 1)),
        makeRoom('b', lastMessageTime: DateTime(2026, 1, 3), pinned: true),
        makeRoom('c', lastMessageTime: DateTime(2026, 1, 5)),
      ]);
      expect(controller.rooms.first.id, 'b');
    });
  });

  group('setRooms', () {
    test('replaces all rooms', () {
      controller.setRooms([makeRoom('x')]);
      expect(controller.rooms, hasLength(1));
      expect(controller.rooms.first.id, 'x');
    });
  });

  group('addRoom', () {
    test('adds new room and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.addRoom(makeRoom('4'));
      expect(controller.rooms, hasLength(4));
      expect(notified, true);
    });

    test('deduplicates by id', () {
      controller.addRoom(makeRoom('1'));
      expect(controller.rooms, hasLength(3));
    });
  });

  group('updateRoom', () {
    test('updates existing room', () {
      controller.updateRoom(makeRoom('1', name: 'Updated'));
      final room = controller.allRooms.firstWhere((r) => r.id == '1');
      expect(room.name, 'Updated');
    });

    test('ignores non-existing room', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.updateRoom(makeRoom('999'));
      expect(notified, false);
    });
  });

  group('removeRoom', () {
    test('removes by id', () {
      controller.removeRoom('1');
      expect(controller.rooms, hasLength(2));
    });

    test('clears selection on remove', () {
      controller.toggleSelect('1');
      controller.removeRoom('1');
      expect(controller.selectedIds, isEmpty);
    });
  });

  group('mergeRooms', () {
    test('non-authoritative merge upserts without dropping unknown rows', () {
      controller.mergeRooms([
        makeRoom('2', name: 'Two Updated'),
        makeRoom('new', name: 'New Room'),
      ], authoritative: false);

      expect(controller.allRooms.map((r) => r.id).toSet(), {
        '1',
        '2',
        '3',
        'new',
      });
      expect(
        controller.allRooms.firstWhere((r) => r.id == '2').name,
        'Two Updated',
      );
    });

    test('non-authoritative merge with empty incoming is a no-op', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.mergeRooms(const [], authoritative: false);

      expect(controller.allRooms, hasLength(3));
      expect(notified, false);
    });

    test('authoritative merge drops rows missing from incoming', () {
      controller.mergeRooms([
        makeRoom('1', name: 'One'),
        makeRoom('new', name: 'New Room'),
      ], authoritative: true);

      expect(controller.allRooms.map((r) => r.id).toSet(), {'1', 'new'});
    });

    test('authoritative merge with empty incoming prunes every known row — a '
        'successful authoritative snapshot is the truth even when empty', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.mergeRooms(const [], authoritative: true);

      expect(controller.allRooms, isEmpty);
      expect(notified, true);
    });

    test(
      'authoritative merge with empty incoming clears an already-empty list',
      () {
        controller.setRooms(const []);
        controller.mergeRooms(const [], authoritative: true);
        expect(controller.allRooms, isEmpty);
      },
    );

    test('authoritative merge clears selection/typing for dropped rows', () {
      controller.toggleSelect('1');
      controller.setRoomTyping('1', 'bob', true);

      controller.mergeRooms([
        makeRoom('2'),
        makeRoom('3'),
      ], authoritative: true);

      expect(controller.selectedIds, isEmpty);
    });

    test('merge does not notify when nothing actually changed', () {
      var notified = false;
      controller.mergeRooms([
        makeRoom('1', lastMessageTime: DateTime(2026, 1, 1)),
        makeRoom('2', lastMessageTime: DateTime(2026, 1, 3)),
        makeRoom('3', lastMessageTime: DateTime(2026, 1, 2)),
      ], authoritative: true);
      controller.addListener(() => notified = true);

      controller.mergeRooms([
        makeRoom('1', lastMessageTime: DateTime(2026, 1, 1)),
        makeRoom('2', lastMessageTime: DateTime(2026, 1, 3)),
        makeRoom('3', lastMessageTime: DateTime(2026, 1, 2)),
      ], authoritative: true);

      expect(notified, false);
    });

    test('authoritative merge spares a room created locally after the snapshot '
        'was captured, even when the snapshot omits it (R2-10)', () {
      // Snapshot captured a moment ago...
      final snapshotAt = DateTime.now().subtract(const Duration(seconds: 1));
      // ...then the user creates a conversation locally (stamped now).
      controller.addRoom(makeRoom('new'));

      // The in-flight snapshot predates the creation and doesn't list it —
      // it must NOT drop the freshly-created room.
      controller.mergeRooms(
        [makeRoom('1'), makeRoom('2'), makeRoom('3')],
        authoritative: true,
        snapshotAt: snapshotAt,
      );

      expect(controller.allRooms.map((r) => r.id).toSet(), {
        '1',
        '2',
        '3',
        'new',
      });
    });

    test('authoritative merge drops a locally-created room when the snapshot '
        'post-dates its creation (genuine server absence)', () {
      controller.addRoom(makeRoom('new'));
      // Snapshot captured AFTER the local creation: the server had a chance
      // to include the room and didn't → genuine absence, drop it.
      final snapshotAt = DateTime.now().add(const Duration(seconds: 1));

      controller.mergeRooms(
        [makeRoom('1'), makeRoom('2'), makeRoom('3')],
        authoritative: true,
        snapshotAt: snapshotAt,
      );

      expect(controller.allRooms.map((r) => r.id), isNot(contains('new')));
    });

    test(
      'an authoritative snapshot that includes a locally-created room clears '
      'its recency protection so a later absence can reconcile it',
      () {
        final snapshotAt = DateTime.now().subtract(const Duration(seconds: 1));
        controller.addRoom(makeRoom('new'));
        // First snapshot confirms the room (server now vouches for it).
        controller.mergeRooms(
          [makeRoom('1'), makeRoom('new')],
          authoritative: true,
          snapshotAt: snapshotAt,
        );
        expect(controller.allRooms.map((r) => r.id), contains('new'));

        // A second snapshot — still predating the original local creation —
        // omits it. With the stamp cleared it is now a genuine absence.
        controller.mergeRooms(
          [makeRoom('1')],
          authoritative: true,
          snapshotAt: snapshotAt,
        );
        expect(controller.allRooms.map((r) => r.id), ['1']);
      },
    );

    test('authoritative empty snapshot WITH a capture time prunes every stale '
        'row — with an honest backend a successful 200 (even empty) is the '
        'complete room set, so it converges the list instead of being treated '
        'as a suspected blip (post-N0: backend now fails outright on a bad '
        'read instead of answering 200 with a partial page)', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.mergeRooms(
        const [],
        authoritative: true,
        snapshotAt: DateTime.now(),
      );

      expect(controller.allRooms, isEmpty);
      expect(notified, true);
    });

    test('authoritative empty snapshot drops the STALE rows but still spares '
        'a room created locally AFTER the snapshot was captured (recency '
        'guard is the only thing left standing between an empty snapshot and '
        'a full wipe)', () {
      final snapshotAt = DateTime.now().subtract(const Duration(seconds: 1));
      controller.addRoom(makeRoom('fresh'));

      controller.mergeRooms(
        const [],
        authoritative: true,
        snapshotAt: snapshotAt,
      );

      expect(controller.allRooms.map((r) => r.id).toSet(), {'fresh'});
    });

    test('authoritative empty snapshot WITHOUT a capture time clears the list '
        '(no recency signal to spare anything — the snapshot is unconditional '
        'truth)', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.mergeRooms(const [], authoritative: true);

      expect(controller.allRooms, isEmpty);
      expect(notified, true);
    });

    test('a PARTIAL authoritative snapshot (non-empty, omitting a room) still '
        'prunes the missing one — only a totally empty incoming is protected '
        '(N0 test c / pull-to-refresh parity)', () {
      controller.mergeRooms(
        [makeRoom('1'), makeRoom('2')],
        authoritative: true,
        snapshotAt: DateTime.now(),
      );

      expect(controller.allRooms.map((r) => r.id).toSet(), {'1', '2'});
    });
  });

  group('filter', () {
    test('filters rooms by name', () {
      controller.setRooms([
        makeRoom('a', name: 'Alice'),
        makeRoom('b', name: 'Bob'),
        makeRoom('c', name: 'Charlie'),
      ]);
      controller.setFilter('ali');
      expect(controller.rooms, hasLength(1));
      expect(controller.rooms.first.id, 'a');
    });

    test('filters rooms by last message', () {
      controller.setRooms([
        const RoomListItem(id: 'a', name: 'Room A', lastMessage: 'hello world'),
        const RoomListItem(id: 'b', name: 'Room B', lastMessage: 'goodbye'),
      ]);
      controller.setFilter('hello');
      expect(controller.rooms, hasLength(1));
    });

    test('empty filter shows all', () {
      controller.setFilter('xyz');
      expect(controller.rooms, isEmpty);
      controller.setFilter('');
      expect(controller.rooms, hasLength(3));
    });

    test('does not notify when same filter', () {
      controller.setFilter('test');
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setFilter('test');
      expect(notified, false);
    });
  });

  group('getRoomById', () {
    test('returns room by ID (O(1) lookup)', () {
      final room = controller.getRoomById('2');
      expect(room, isNotNull);
      expect(room!.id, '2');
      expect(room.name, 'Room 2');
    });

    test('returns null for unknown ID', () {
      expect(controller.getRoomById('unknown'), isNull);
    });

    test('returns updated room after updateRoom', () {
      controller.updateRoom(makeRoom('1', name: 'Renamed'));
      final room = controller.getRoomById('1');
      expect(room, isNotNull);
      expect(room!.name, 'Renamed');
    });
  });

  group('selection', () {
    test('toggleSelect adds and removes', () {
      controller.toggleSelect('1');
      expect(controller.selectedIds, {'1'});
      expect(controller.isSelecting, true);

      controller.toggleSelect('1');
      expect(controller.selectedIds, isEmpty);
      expect(controller.isSelecting, false);
    });

    test('clearSelection clears all', () {
      controller.toggleSelect('1');
      controller.toggleSelect('2');
      controller.clearSelection();
      expect(controller.selectedIds, isEmpty);
    });

    test('clearSelection does not notify when empty', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.clearSelection();
      expect(notified, false);
    });
  });
}
