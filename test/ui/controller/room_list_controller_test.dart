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
        RoomListItem(id: 'a', name: 'Room A', lastMessage: 'hello world'),
        RoomListItem(id: 'b', name: 'Room B', lastMessage: 'goodbye'),
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
