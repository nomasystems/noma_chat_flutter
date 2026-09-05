import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListController — filter by participant name', () {
    test(
      'a query matching only a member returns the room with its matchedParticipant',
      () {
        final controller = RoomListController(
          initialRooms: const [
            RoomListItem(
              id: 'group-1',
              name: 'Weekend trip',
              lastMessage: 'see you there',
              isGroup: true,
            ),
          ],
          participantNameResolver: (room) =>
              room.id == 'group-1' ? const ['Alice', 'Bob'] : const [],
        );

        controller.setFilter('ali');

        expect(controller.rooms.map((r) => r.id), ['group-1']);
        expect(controller.matchedParticipantFor('group-1'), 'Alice');
      },
    );

    test('matchedParticipantFor is null for a title/last-message match', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'r1', name: 'Alice', lastMessage: 'hi'),
        ],
        participantNameResolver: (room) => const ['Alice'],
      )..setFilter('alice');

      expect(controller.rooms.map((r) => r.id), ['r1']);
      expect(controller.matchedParticipantFor('r1'), isNull);
    });

    test('no resolver wired: participant text never matches', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'r1', name: 'Weekend trip', isGroup: true),
        ],
      )..setFilter('alice');

      expect(controller.rooms, isEmpty);
    });

    test('resolver returning no match leaves the room filtered out', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'r1', name: 'Weekend trip', isGroup: true),
        ],
        participantNameResolver: (room) => const ['Charlie'],
      )..setFilter('alice');

      expect(controller.rooms, isEmpty);
      expect(controller.matchedParticipantFor('r1'), isNull);
    });

    test('filters by resolved title (effectiveDisplayName), not raw name', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'dm-1', effectiveDisplayName: 'Alice Johnson'),
        ],
      )..setFilter('john');

      expect(controller.rooms.map((r) => r.id), ['dm-1']);
    });

    test('unread badge count ignores the participant-name filter', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(
            id: 'group-1',
            name: 'Weekend trip',
            isGroup: true,
            unreadCount: 3,
          ),
          RoomListItem(id: 'r2', name: 'Other', unreadCount: 2),
        ],
        participantNameResolver: (room) =>
            room.id == 'group-1' ? const ['Alice'] : const [],
      );

      controller.setFilter('ali');
      expect(controller.rooms.map((r) => r.id), ['group-1']);
      // unreadRoomCount is the count of CONVERSATIONS with unread messages,
      // not a sum of unreadCount — both rooms qualify, filter or no filter.
      expect(controller.unreadRoomCount(), 2);
    });

    test(
      'archived rooms are still filtered separately by participant name',
      () {
        final controller = RoomListController(
          initialRooms: const [
            RoomListItem(id: 'active-1', name: 'Active group', isGroup: true),
            RoomListItem(
              id: 'archived-1',
              name: 'Archived group',
              isGroup: true,
              hidden: true,
            ),
          ],
          participantNameResolver: (room) => const ['Alice'],
        )..setFilter('ali');

        expect(controller.rooms.map((r) => r.id), ['active-1']);
        expect(controller.archivedRooms.map((r) => r.id), ['archived-1']);
        expect(controller.matchedParticipantFor('active-1'), 'Alice');
        expect(controller.matchedParticipantFor('archived-1'), 'Alice');
      },
    );

    test('notifyMembersChanged re-evaluates the participant filter', () {
      var names = const <String>[];
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'r1', name: 'Weekend trip', isGroup: true),
        ],
        participantNameResolver: (room) => names,
      )..setFilter('alice');

      expect(controller.rooms, isEmpty);

      names = const ['Alice'];
      controller.notifyMembersChanged();

      expect(controller.rooms.map((r) => r.id), ['r1']);
      expect(controller.matchedParticipantFor('r1'), 'Alice');
    });

    test('a renamed room stays findable by its raw server name', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(
            id: 'r1',
            name: 'Weekend trip',
            effectiveDisplayName: 'Escapada',
            isGroup: true,
          ),
        ],
      );

      controller.setFilter('escapada');
      expect(controller.rooms.map((r) => r.id), ['r1']);

      controller.setFilter('weekend');
      expect(controller.rooms.map((r) => r.id), ['r1']);
      expect(controller.matchedParticipantFor('r1'), isNull);
    });

    test('setParticipantNameResolver swaps the resolver and re-filters', () {
      final controller = RoomListController(
        initialRooms: const [
          RoomListItem(id: 'r1', name: 'Weekend trip', isGroup: true),
        ],
      )..setFilter('alice');

      expect(controller.rooms, isEmpty);

      controller.setParticipantNameResolver((room) => const ['Alice']);

      expect(controller.rooms.map((r) => r.id), ['r1']);
    });
  });
}
