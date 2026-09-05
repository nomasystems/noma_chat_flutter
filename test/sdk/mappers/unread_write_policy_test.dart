import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
import 'package:noma_chat/src/cache/serialization.dart';

/// The write policy has a single source on the wire — `config.writePolicy` —
/// and it has to survive both reads of a room: the listing projection and
/// the cached snapshot the list is rebuilt from on a cold start.
void main() {
  group('listing projection', () {
    test('reads owner_only out of config', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'config': {'allowInvitations': false, 'writePolicy': 'owner_only'},
      });
      expect(unread.writePolicy, RoomWritePolicy.ownerOnly);
    });

    test('defaults to members when the field is absent', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'config': {'allowInvitations': true},
      });
      expect(unread.writePolicy, RoomWritePolicy.members);
    });

    test('defaults to members when there is no config at all', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
      });
      expect(unread.writePolicy, RoomWritePolicy.members);
    });

    test('an unknown value fails open instead of locking the room', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'config': {'writePolicy': 'admins_only'},
      });
      expect(unread.writePolicy, RoomWritePolicy.members);
    });

    test('a config that is not an object is ignored', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'config': 'owner_only',
      });
      expect(unread.writePolicy, RoomWritePolicy.members);
    });

    test('custom is never a source for the policy', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'custom': {'writePolicy': 'owner_only'},
      });
      expect(unread.writePolicy, RoomWritePolicy.members);
    });
  });

  group('cache round-trip', () {
    test('an owner-only listing row survives toMap/fromMap', () {
      const original = UnreadRoom(
        roomId: 'r1',
        unreadMessages: 2,
        writePolicy: RoomWritePolicy.ownerOnly,
      );
      expect(
        unreadRoomFromMap(unreadRoomToMap(original)).writePolicy,
        RoomWritePolicy.ownerOnly,
      );
    });

    test('a members row writes nothing and reads back as members', () {
      const original = UnreadRoom(roomId: 'r1', unreadMessages: 0);
      final map = unreadRoomToMap(original);
      expect(map.containsKey('writePolicy'), isFalse);
      expect(unreadRoomFromMap(map).writePolicy, RoomWritePolicy.members);
    });

    test('an owner-only detail survives toMap/fromMap', () {
      const detail = RoomDetail(
        id: 'r1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.member,
        config: RoomConfig(writePolicy: RoomWritePolicy.ownerOnly),
      );
      final restored = roomDetailFromMap(roomDetailToMap(detail));
      expect(restored.config.writePolicy, RoomWritePolicy.ownerOnly);
      expect(restored.isReadOnly, isTrue);
    });

    test('a detail cached before the policy existed reads as members', () {
      final restored = roomDetailFromMap({
        'id': 'r1',
        'type': 'group',
        'memberCount': 3,
        'userRole': 'member',
        'allowInvitations': false,
      });
      expect(restored.config.writePolicy, RoomWritePolicy.members);
      expect(restored.isReadOnly, isFalse);
    });
  });
}
