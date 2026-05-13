import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('cached filtered room list', () {
    test('returns same list instance on repeated access without changes', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
        const RoomListItem(id: 'b', name: 'Bob'),
      ]);

      controller.setFilter('ali');
      final first = controller.rooms;
      final second = controller.rooms;

      expect(identical(first, second), true);

      controller.dispose();
    });

    test('invalidates cache when rooms change', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
        const RoomListItem(id: 'b', name: 'Bob'),
      ]);

      controller.setFilter('ali');
      final beforeAdd = controller.rooms;
      expect(beforeAdd, hasLength(1));

      controller.addRoom(const RoomListItem(id: 'c', name: 'Alicia'));
      final afterAdd = controller.rooms;

      expect(identical(beforeAdd, afterAdd), false);
      expect(afterAdd, hasLength(2));

      controller.dispose();
    });

    test('invalidates cache when filter changes', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
        const RoomListItem(id: 'b', name: 'Bob'),
      ]);

      controller.setFilter('ali');
      final first = controller.rooms;
      expect(first, hasLength(1));

      controller.setFilter('bob');
      final second = controller.rooms;
      expect(second, hasLength(1));
      expect(second.first.id, 'b');
      expect(identical(first, second), false);

      controller.dispose();
    });

    test('invalidates cache on updateRoom', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
        const RoomListItem(id: 'b', name: 'Bob'),
      ]);

      controller.setFilter('ali');
      final before = controller.rooms;
      expect(before, hasLength(1));

      controller.updateRoom(const RoomListItem(id: 'b', name: 'Alix'));
      final after = controller.rooms;
      expect(after, hasLength(2));
      expect(identical(before, after), false);

      controller.dispose();
    });

    test('invalidates cache on removeRoom', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
        const RoomListItem(id: 'b', name: 'Alina'),
      ]);

      controller.setFilter('ali');
      final before = controller.rooms;
      expect(before, hasLength(2));

      controller.removeRoom('a');
      final after = controller.rooms;
      expect(after, hasLength(1));
      expect(identical(before, after), false);

      controller.dispose();
    });

    test('invalidates cache on setRooms', () {
      final controller = RoomListController(initialRooms: [
        const RoomListItem(id: 'a', name: 'Alice'),
      ]);

      controller.setFilter('ali');
      final before = controller.rooms;
      expect(before, hasLength(1));

      controller.setRooms([
        const RoomListItem(id: 'x', name: 'Xavier'),
      ]);
      final after = controller.rooms;
      expect(after, isEmpty);
      expect(identical(before, after), false);

      controller.dispose();
    });
  });
}
