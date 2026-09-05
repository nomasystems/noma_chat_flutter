import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';

/// [RoomDetail.config.writePolicy] is read from the room's `config` in the
/// detail response — the same JSON shape the SDK re-fetches to refresh a
/// listed room and to react to a `room_updated` event — and never from
/// `custom`, which a support room already uses for `support`/`reportRef`.
/// See bloque 03-noma-sdk.md section E.
void main() {
  Map<String, dynamic> detailJson({
    String userRole = 'user',
    Map<String, dynamic>? config,
    Map<String, dynamic>? custom,
  }) => {
    'id': 'room-1',
    'name': 'Room',
    'type': 'group',
    'memberCount': 3,
    'userRole': userRole,
    if (config != null) 'config': config,
    if (custom != null) 'custom': custom,
  };

  group('RoomMapper.detailFromJson: writePolicy source', () {
    test('reads owner_only from config.writePolicy', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(config: {'writePolicy': 'owner_only'}),
      );
      expect(detail.config.writePolicy, RoomWritePolicy.ownerOnly);
    });

    test('config missing entirely resolves to members', () {
      final detail = RoomMapper.detailFromJson(detailJson());
      expect(detail.config.writePolicy, RoomWritePolicy.members);
    });

    test('config present without writePolicy resolves to members', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(config: {'allowInvitations': true}),
      );
      expect(detail.config.writePolicy, RoomWritePolicy.members);
    });

    test('an unrecognised value resolves to members', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(config: {'writePolicy': 'moderators'}),
      );
      expect(detail.config.writePolicy, RoomWritePolicy.members);
    });

    test('never reads writePolicy from custom, even when config has none', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(custom: {'writePolicy': 'owner_only', 'support': true}),
      );
      expect(detail.config.writePolicy, RoomWritePolicy.members);
    });

    test(
      'custom carrying owner_only cannot override an explicit config value',
      () {
        final detail = RoomMapper.detailFromJson(
          detailJson(
            config: {'writePolicy': 'members'},
            custom: {'writePolicy': 'owner_only'},
          ),
        );
        expect(detail.config.writePolicy, RoomWritePolicy.members);
      },
    );
  });

  group('RoomDetail.isReadOnly with writePolicy', () {
    test('owner_only room is read-only for a plain member', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(userRole: 'user', config: {'writePolicy': 'owner_only'}),
      );
      expect(detail.isReadOnly, isTrue);
    });

    test('owner_only room is writable for its owner', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(userRole: 'owner', config: {'writePolicy': 'owner_only'}),
      );
      expect(detail.isReadOnly, isFalse);
    });

    test('members policy (default) leaves a plain member able to write', () {
      final detail = RoomMapper.detailFromJson(detailJson(userRole: 'user'));
      expect(detail.isReadOnly, isFalse);
    });

    test('an admin is still read-only in an owner_only room', () {
      final detail = RoomMapper.detailFromJson(
        detailJson(userRole: 'admin', config: {'writePolicy': 'owner_only'}),
      );
      expect(detail.isReadOnly, isTrue);
    });
  });

  group('RoomListItem.isReadOnly with writePolicy', () {
    test('owner_only + non-owner role is read-only', () {
      const room = RoomListItem(
        id: 'r1',
        writePolicy: RoomWritePolicy.ownerOnly,
        userRole: RoomRole.member,
      );
      expect(room.isReadOnly, isTrue);
    });

    test('owner_only + owner role stays writable', () {
      const room = RoomListItem(
        id: 'r1',
        writePolicy: RoomWritePolicy.ownerOnly,
        userRole: RoomRole.owner,
      );
      expect(room.isReadOnly, isFalse);
    });

    test('default writePolicy (members) does not force read-only', () {
      const room = RoomListItem(id: 'r1', userRole: RoomRole.member);
      expect(room.writePolicy, RoomWritePolicy.members);
      expect(room.isReadOnly, isFalse);
    });

    test('announcement and selfMuted keep forcing read-only on their own', () {
      const announcement = RoomListItem(
        id: 'r1',
        isAnnouncement: true,
        userRole: RoomRole.member,
      );
      const muted = RoomListItem(id: 'r1', selfMuted: true);
      expect(announcement.isReadOnly, isTrue);
      expect(muted.isReadOnly, isTrue);
    });

    test('equality detects writePolicy changes', () {
      const a = RoomListItem(id: 'r1');
      const b = RoomListItem(id: 'r1', writePolicy: RoomWritePolicy.ownerOnly);
      expect(a, isNot(equals(b)));
    });
  });
}
