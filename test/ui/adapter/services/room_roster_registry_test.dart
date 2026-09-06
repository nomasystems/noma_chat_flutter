import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/room_roster_registry.dart';

/// The room list filter runs synchronously on every keystroke, so the
/// registry it reads has to answer without awaiting anything — and stay
/// bounded, because it lives for as long as the session does.
void main() {
  test('a room whose roster was never seen has no members', () {
    expect(RoomRosterRegistry().membersOf('r1'), isEmpty);
    expect(RoomRosterRegistry().knows('r1'), isFalse);
  });

  test('recording replaces, adding merges', () {
    final registry = RoomRosterRegistry();
    registry.record('r1', ['u1', 'u2']);
    expect(registry.membersOf('r1'), {'u1', 'u2'});

    registry.addAll('r1', ['u3']);
    expect(registry.membersOf('r1'), {'u1', 'u2', 'u3'});

    registry.record('r1', ['u4']);
    expect(registry.membersOf('r1'), {'u4'});
  });

  test('empty ids are dropped rather than recorded', () {
    final registry = RoomRosterRegistry();
    registry.record('r1', ['', 'u1', '']);
    expect(registry.membersOf('r1'), {'u1'});

    registry.record('', ['u1']);
    expect(registry.length, 1);
  });

  test('a member removal leaves an unknown roster unknown', () {
    final registry = RoomRosterRegistry();
    registry.remove('r1', 'u1');
    expect(registry.knows('r1'), isFalse);

    registry.record('r1', ['u1', 'u2']);
    registry.remove('r1', 'u1');
    expect(registry.membersOf('r1'), {'u2'});
  });

  test('forgetting one room leaves the others alone', () {
    final registry = RoomRosterRegistry();
    registry.record('r1', ['u1']);
    registry.record('r2', ['u2']);

    registry.forget('r1');
    expect(registry.knows('r1'), isFalse);
    expect(registry.membersOf('r2'), {'u2'});

    registry.clear();
    expect(registry.length, 0);
  });

  test('a community-sized group stops at the member cap', () {
    final registry = RoomRosterRegistry(maxMembersPerRoom: 3);
    registry.record('r1', ['u1', 'u2', 'u3', 'u4', 'u5']);
    expect(registry.membersOf('r1').length, 3);

    registry.addAll('r1', ['u6']);
    expect(registry.membersOf('r1').length, 3);
  });

  test('the least recently recorded room is the one evicted', () {
    final registry = RoomRosterRegistry(maxRooms: 2);
    registry.record('r1', ['u1']);
    registry.record('r2', ['u2']);
    registry.record('r3', ['u3']);

    expect(registry.knows('r1'), isFalse);
    expect(registry.membersOf('r2'), {'u2'});
    expect(registry.membersOf('r3'), {'u3'});

    registry.addAll('r2', ['u9']);
    registry.record('r4', ['u4']);
    expect(registry.knows('r2'), isTrue);
    expect(registry.knows('r3'), isFalse);
  });
}
