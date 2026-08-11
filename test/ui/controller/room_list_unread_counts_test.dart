import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListController — unread conversation counters', () {
    test('splits unread rooms between the main list and the archive', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', name: 'Active unread', unreadCount: 3),
          RoomListItem(id: 'b', name: 'Active read'),
          RoomListItem(
            id: 'c',
            name: 'Archived unread',
            hidden: true,
            unreadCount: 1,
          ),
          RoomListItem(id: 'd', name: 'Archived read', hidden: true),
        ],
      );

      expect(controller.unreadRoomCount(), 1);
      expect(controller.unreadArchivedRoomCount(), 1);
    });

    test('counts conversations, not messages', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', unreadCount: 12),
          RoomListItem(id: 'b', unreadCount: 7),
        ],
      );

      expect(controller.unreadRoomCount(), 2);
    });

    test('excludes muted rooms by default, includes them on request', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', unreadCount: 1),
          RoomListItem(id: 'b', unreadCount: 1, muted: true),
          RoomListItem(id: 'c', unreadCount: 1, hidden: true),
          RoomListItem(id: 'd', unreadCount: 1, hidden: true, muted: true),
        ],
      );

      expect(controller.unreadRoomCount(), 1);
      expect(controller.unreadArchivedRoomCount(), 1);
      expect(controller.unreadRoomCount(includeMuted: true), 2);
      expect(controller.unreadArchivedRoomCount(includeMuted: true), 2);
    });

    test('excludes per-user deleted rooms from both counters', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', unreadCount: 1),
          RoomListItem(id: 'b', unreadCount: 1),
          RoomListItem(id: 'c', unreadCount: 1, hidden: true),
          RoomListItem(id: 'd', unreadCount: 1, hidden: true),
        ],
      )..setDeletedRoomIds({'b', 'd'});

      expect(controller.unreadRoomCount(), 1);
      expect(controller.unreadArchivedRoomCount(), 1);
    });

    test('ignores the active text filter', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a', name: 'Alpha', unreadCount: 1),
          RoomListItem(id: 'b', name: 'Beta', unreadCount: 1),
          RoomListItem(id: 'c', name: 'Gamma', hidden: true, unreadCount: 1),
          RoomListItem(id: 'd', name: 'Delta', hidden: true, unreadCount: 1),
        ],
      )..setFilter('alph');

      expect(controller.rooms.map((r) => r.id), ['a']);
      expect(controller.archivedRooms, isEmpty);
      expect(controller.unreadRoomCount(), 2);
      expect(controller.unreadArchivedRoomCount(), 2);
    });

    test('archiving an unread room moves it between the two counters', () {
      final controller = RoomListController(
        initialRooms: const [RoomListItem(id: 'a', unreadCount: 2)],
      );
      expect(controller.unreadRoomCount(), 1);
      expect(controller.unreadArchivedRoomCount(), 0);

      controller.updateRoom(
        controller.getRoomById('a')!.copyWith(hidden: true),
      );

      expect(controller.unreadRoomCount(), 0);
      expect(controller.unreadArchivedRoomCount(), 1);
    });

    test('both counters are zero with nothing unread', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'a'),
          RoomListItem(id: 'b', hidden: true),
        ],
      );

      expect(controller.unreadRoomCount(includeMuted: true), 0);
      expect(controller.unreadArchivedRoomCount(includeMuted: true), 0);
    });
  });
}
