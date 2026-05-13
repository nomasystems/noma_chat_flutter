import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListItem', () {
    test('equality compares all fields', () {
      final a = RoomListItem(id: 'r1', name: 'A');
      final b = RoomListItem(id: 'r1', name: 'A');
      final c = RoomListItem(id: 'r1', name: 'B');
      final d = RoomListItem(id: 'r2', name: 'A');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('equality detects unreadCount changes', () {
      final a = RoomListItem(id: 'r1', unreadCount: 0);
      final b = RoomListItem(id: 'r1', unreadCount: 5);
      expect(a, isNot(equals(b)));
    });

    test('equality detects muted changes', () {
      final a = RoomListItem(id: 'r1', muted: false);
      final b = RoomListItem(id: 'r1', muted: true);
      expect(a, isNot(equals(b)));
    });

    test('equality detects pinned changes', () {
      final a = RoomListItem(id: 'r1', pinned: false);
      final b = RoomListItem(id: 'r1', pinned: true);
      expect(a, isNot(equals(b)));
    });

    test('equality detects isOnline changes', () {
      final a = RoomListItem(id: 'r1', isOnline: null);
      final b = RoomListItem(id: 'r1', isOnline: true);
      final c = RoomListItem(id: 'r1', isOnline: false);
      expect(a, isNot(equals(b)));
      expect(b, isNot(equals(c)));
      expect(a, isNot(equals(c)));
    });

    test('copyWith preserves fields', () {
      final original = RoomListItem(
        id: 'r1',
        name: 'Room',
        unreadCount: 5,
        muted: true,
      );
      final updated = original.copyWith(name: 'New Name');
      expect(updated.id, 'r1');
      expect(updated.name, 'New Name');
      expect(updated.unreadCount, 5);
      expect(updated.muted, true);
    });

    test('copyWith changes unreadCount', () {
      final room = RoomListItem(id: 'r1', unreadCount: 10);
      final updated = room.copyWith(unreadCount: 0);
      expect(updated.unreadCount, 0);
    });

    test('equality detects custom changes by reference', () {
      final custom1 = {'key': 'value1'};
      final custom2 = {'key': 'value2'};
      final a = RoomListItem(id: 'r1', custom: custom1);
      final b = RoomListItem(id: 'r1', custom: custom2);
      final c = RoomListItem(id: 'r1', custom: custom1);
      expect(a, isNot(equals(b)));
      expect(a, equals(c));
    });

    test('isInvitation returns true when custom has invited flag', () {
      final invited = RoomListItem(
        id: 'r1',
        custom: const {'invited': true, 'invitedBy': 'u2'},
      );
      expect(invited.isInvitation, true);

      final notInvited = RoomListItem(id: 'r2');
      expect(notInvited.isInvitation, false);

      final invitedFalse = RoomListItem(
        id: 'r3',
        custom: const {'invited': false},
      );
      expect(invitedFalse.isInvitation, false);
    });

    test('hashCode is consistent with equality', () {
      final a = RoomListItem(id: 'r1', name: 'A', unreadCount: 5);
      final b = RoomListItem(id: 'r1', name: 'A', unreadCount: 5);
      expect(a.hashCode, equals(b.hashCode));

      final c = RoomListItem(id: 'r1', name: 'A', avatarUrl: 'http://img');
      final d = RoomListItem(id: 'r1', name: 'A');
      expect(c, isNot(equals(d)));
    });

    test('equality detects isAnnouncement changes', () {
      final a = RoomListItem(id: 'r1', isAnnouncement: false);
      final b = RoomListItem(id: 'r1', isAnnouncement: true);
      expect(a, isNot(equals(b)));
    });

    test('isReadOnly true for announcement non-owner', () {
      final room = RoomListItem(
        id: 'r1',
        isAnnouncement: true,
        userRole: RoomRole.member,
      );
      expect(room.isReadOnly, isTrue);
    });

    test('isReadOnly false for announcement owner', () {
      final room = RoomListItem(
        id: 'r1',
        isAnnouncement: true,
        userRole: RoomRole.owner,
      );
      expect(room.isReadOnly, isFalse);
    });

    test('isReadOnly false for non-announcement room', () {
      final room = RoomListItem(
        id: 'r1',
        isAnnouncement: false,
        userRole: RoomRole.member,
      );
      expect(room.isReadOnly, isFalse);
    });

    test('copyWith preserves isAnnouncement', () {
      final original = RoomListItem(id: 'r1', isAnnouncement: true);
      final updated = original.copyWith(name: 'New');
      expect(updated.isAnnouncement, isTrue);
    });
  });
}
