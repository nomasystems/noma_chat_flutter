import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('RoomListItem', () {
    test('equality compares all fields', () {
      const a = RoomListItem(id: 'r1', name: 'A');
      const b = RoomListItem(id: 'r1', name: 'A');
      const c = RoomListItem(id: 'r1', name: 'B');
      const d = RoomListItem(id: 'r2', name: 'A');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('equality detects unreadCount changes', () {
      const a = RoomListItem(id: 'r1', unreadCount: 0);
      const b = RoomListItem(id: 'r1', unreadCount: 5);
      expect(a, isNot(equals(b)));
    });

    test('equality detects muted changes', () {
      const a = RoomListItem(id: 'r1', muted: false);
      const b = RoomListItem(id: 'r1', muted: true);
      expect(a, isNot(equals(b)));
    });

    test('equality detects pinned changes', () {
      const a = RoomListItem(id: 'r1', pinned: false);
      const b = RoomListItem(id: 'r1', pinned: true);
      expect(a, isNot(equals(b)));
    });

    test('equality detects isOnline changes', () {
      const a = RoomListItem(id: 'r1', isOnline: null);
      const b = RoomListItem(id: 'r1', isOnline: true);
      const c = RoomListItem(id: 'r1', isOnline: false);
      expect(a, isNot(equals(b)));
      expect(b, isNot(equals(c)));
      expect(a, isNot(equals(c)));
    });

    test('copyWith preserves fields', () {
      const original = RoomListItem(
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
      const room = RoomListItem(id: 'r1', unreadCount: 10);
      final updated = room.copyWith(unreadCount: 0);
      expect(updated.unreadCount, 0);
    });

    test('lastSeen defaults to null and round-trips through copyWith', () {
      const room = RoomListItem(id: 'r1');
      expect(room.lastSeen, isNull);

      final seenAt = DateTime.utc(2026, 1, 1, 12);
      final updated = room.copyWith(lastSeen: seenAt);
      expect(updated.lastSeen, seenAt);
    });

    test('equality detects lastSeen changes', () {
      final a = RoomListItem(id: 'r1', lastSeen: DateTime.utc(2026, 1, 1));
      final b = RoomListItem(id: 'r1', lastSeen: DateTime.utc(2026, 1, 2));
      const c = RoomListItem(id: 'r1');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
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
      const invited = RoomListItem(
        id: 'r1',
        custom: {'invited': true, 'invitedBy': 'u2'},
      );
      expect(invited.isInvitation, true);

      const notInvited = RoomListItem(id: 'r2');
      expect(notInvited.isInvitation, false);

      const invitedFalse = RoomListItem(id: 'r3', custom: {'invited': false});
      expect(invitedFalse.isInvitation, false);
    });

    test('hashCode is consistent with equality', () {
      const a = RoomListItem(id: 'r1', name: 'A', unreadCount: 5);
      const b = RoomListItem(id: 'r1', name: 'A', unreadCount: 5);
      expect(a.hashCode, equals(b.hashCode));

      const c = RoomListItem(id: 'r1', name: 'A', avatarUrl: 'http://img');
      const d = RoomListItem(id: 'r1', name: 'A');
      expect(c, isNot(equals(d)));
    });

    test('equality detects isAnnouncement changes', () {
      const a = RoomListItem(id: 'r1', isAnnouncement: false);
      const b = RoomListItem(id: 'r1', isAnnouncement: true);
      expect(a, isNot(equals(b)));
    });

    test('isReadOnly true for announcement non-owner', () {
      const room = RoomListItem(
        id: 'r1',
        isAnnouncement: true,
        userRole: RoomRole.member,
      );
      expect(room.isReadOnly, isTrue);
    });

    test('isReadOnly false for announcement owner', () {
      const room = RoomListItem(
        id: 'r1',
        isAnnouncement: true,
        userRole: RoomRole.owner,
      );
      expect(room.isReadOnly, isFalse);
    });

    test('isReadOnly false for non-announcement room', () {
      const room = RoomListItem(
        id: 'r1',
        isAnnouncement: false,
        userRole: RoomRole.member,
      );
      expect(room.isReadOnly, isFalse);
    });

    test('copyWith preserves isAnnouncement', () {
      const original = RoomListItem(id: 'r1', isAnnouncement: true);
      final updated = original.copyWith(name: 'New');
      expect(updated.isAnnouncement, isTrue);
    });
  });
}
