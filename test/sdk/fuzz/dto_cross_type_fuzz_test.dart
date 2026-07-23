import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/dto/presence_dto.dart';
import 'package:noma_chat/src/_internal/dto/room_dto.dart';
import 'package:noma_chat/src/_internal/dto/user_dto.dart';
import 'package:noma_chat/src/_internal/mappers/health_mapper.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';
import 'package:noma_chat/src/_internal/mappers/presence_mapper.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
import 'package:noma_chat/src/_internal/mappers/user_mapper.dart';

void main() {
  group('RoomDto cross-type fuzz', () {
    test('roomId as int does not throw', () {
      expect(() => RoomDto.fromJson({'roomId': 42}), returnsNormally);
    });

    test('roomId as int is coerced to string, not dropped to empty', () {
      final dto = RoomDto.fromJson({'roomId': 12345, 'name': 'X'});
      expect(dto.roomId, '12345');
    });

    test('id as int is coerced to string when roomId is absent', () {
      final dto = RoomDto.fromJson({'id': 999});
      expect(dto.roomId, '999');
    });

    test('owner as int does not throw', () {
      expect(
        () => RoomDto.fromJson({'roomId': 'r', 'owner': 42}),
        returnsNormally,
      );
    });

    test('allowInvitations as string does not throw', () {
      expect(
        () => RoomDto.fromJson({'roomId': 'r', 'allowInvitations': 'yes'}),
        returnsNormally,
      );
    });

    test('members as a non-list string does not throw', () {
      expect(
        () => RoomDto.fromJson({'roomId': 'r', 'members': 'not-a-list'}),
        returnsNormally,
      );
    });

    test('members with non-string entries drops them instead of throwing '
        'on later iteration', () {
      final dto = RoomDto.fromJson({
        'roomId': 'r',
        'members': ['u1', 42, null, 'u2'],
      });
      expect(() => dto.members?.length, returnsNormally);
      expect(dto.members, ['u1', 'u2']);
    });

    test('custom as a list does not throw', () {
      expect(
        () => RoomDto.fromJson({
          'roomId': 'r',
          'custom': [1, 2, 3],
        }),
        returnsNormally,
      );
    });
  });

  group('RoomDetailDto cross-type fuzz', () {
    test('memberCount as string does not throw', () {
      expect(
        () => RoomDetailDto.fromJson({'id': 'r', 'memberCount': 'five'}),
        returnsNormally,
      );
    });

    test('id as int is coerced to string, not dropped to empty', () {
      final dto = RoomDetailDto.fromJson({'id': 777});
      expect(dto.id, '777');
    });

    test('memberCount as whole double is truncated, not thrown', () {
      final dto = RoomDetailDto.fromJson({'id': 'r', 'memberCount': 5.0});
      expect(dto.memberCount, 5);
    });

    test('type/userRole as int does not throw', () {
      expect(
        () => RoomDetailDto.fromJson({
          'id': 'r',
          'type': 1,
          'userRole': 2,
        }),
        returnsNormally,
      );
    });

    test('muted/pinned/hidden/selfMuted as strings do not throw', () {
      expect(
        () => RoomDetailDto.fromJson({
          'id': 'r',
          'muted': 'true',
          'pinned': 'false',
          'hidden': 1,
          'selfMuted': 0,
        }),
        returnsNormally,
      );
    });

    test('config as a list does not throw', () {
      expect(
        () => RoomDetailDto.fromJson({
          'id': 'r',
          'config': [1, 2],
        }),
        returnsNormally,
      );
    });
  });

  group('UserRoomsDto cross-type fuzz', () {
    test('rooms as a non-list string does not throw', () {
      expect(
        () => UserRoomsDto.fromJson({'rooms': 'not-a-list'}),
        returnsNormally,
      );
    });

    test('rooms list with non-map entries drops them', () {
      final dto = UserRoomsDto.fromJson({
        'rooms': [
          {'roomId': 'r1'},
          'not-a-map',
          42,
          null,
          {'roomId': 'r2'},
        ],
      });
      expect(dto.rooms.length, 2);
    });

    test('hasMore as string does not throw', () {
      expect(
        () => UserRoomsDto.fromJson({'hasMore': 'yes'}),
        returnsNormally,
      );
    });
  });

  group('UserDto cross-type fuzz', () {
    test('active as string does not throw', () {
      expect(
        () => UserDto.fromJson({'id': 'u', 'active': 'yes'}),
        returnsNormally,
      );
    });

    test('id as int is coerced to string, not dropped to empty', () {
      final dto = UserDto.fromJson({'id': 987, 'displayName': 'Alice'});
      expect(dto.id, '987');
    });

    test('userId as int is coerced to string when id is absent', () {
      final dto = UserDto.fromJson({'userId': 654});
      expect(dto.id, '654');
    });

    test('custom/configuration as lists do not throw', () {
      expect(
        () => UserDto.fromJson({
          'id': 'u',
          'custom': [1],
          'configuration': ['x'],
        }),
        returnsNormally,
      );
    });
  });

  group('PresenceDto cross-type fuzz', () {
    test('online as string does not throw', () {
      expect(
        () => PresenceDto.fromJson({'userId': 'u', 'online': 'yes'}),
        returnsNormally,
      );
    });

    test('userId as int is coerced to string, not dropped to empty', () {
      final dto = PresenceDto.fromJson({'userId': 555, 'status': 'online'});
      expect(dto.userId, '555');
    });

    test('status/userId as int do not throw', () {
      expect(
        () => PresenceDto.fromJson({'userId': 1, 'status': 2}),
        returnsNormally,
      );
    });
  });

  group('PresenceMapper.bulkFromJson cross-type fuzz', () {
    test('own as a non-map does not throw', () {
      expect(
        () => PresenceMapper.bulkFromJson({'own': 'not-a-map'}),
        returnsNormally,
      );
    });

    test('contacts as a non-list does not throw', () {
      expect(
        () => PresenceMapper.bulkFromJson({'contacts': 'not-a-list'}),
        returnsNormally,
      );
    });

    test('contacts with non-map entries drops them', () {
      final result = PresenceMapper.bulkFromJson({
        'contacts': [
          {'userId': 'c1'},
          'not-a-map',
          42,
        ],
      });
      expect(result.contacts.length, 1);
    });
  });

  group('RoomMapper supplementary fromJson cross-type fuzz', () {
    test('preferencesFromJson with string bools does not throw', () {
      expect(
        () => RoomMapper.preferencesFromJson({
          'muted': 'yes',
          'pinned': 1,
          'hidden': 0,
        }),
        returnsNormally,
      );
    });

    test('discoveredFromJson with wrong types does not throw', () {
      expect(
        () => RoomMapper.discoveredFromJson({
          'roomId': 42,
          'memberCount': 'five',
          'custom': 'not-a-map',
        }),
        returnsNormally,
      );
    });

    test('discoveredFromJson roomId as int is coerced, not dropped to '
        'empty', () {
      final room = RoomMapper.discoveredFromJson({'roomId': 12345});
      expect(room.id, '12345');
    });

    test('unreadRoomFromJson roomId as int is coerced, not dropped to '
        'empty', () {
      final room = RoomMapper.unreadRoomFromJson({'roomId': 67890});
      expect(room.roomId, '67890');
    });

    test('userRoomsFromDto invitedRooms roomId/invitedBy as int are '
        'coerced, not dropped to empty', () {
      final result = RoomMapper.userRoomsFromDto(
        const UserRoomsDto(
          rooms: [],
          invitedRooms: [
            {'roomId': 42, 'invitedBy': 7, 'roomName': 1},
          ],
        ),
      );
      expect(result.invitedRooms.single.roomId, '42');
      expect(result.invitedRooms.single.invitedBy, '7');
    });

    test('unreadRoomFromJson with wrong top-level types does not throw', () {
      expect(
        () => RoomMapper.unreadRoomFromJson({
          'roomId': 42,
          'unreadMessages': 'five',
          'unreadMentions': 'zero',
          'name': 1,
          'avatarUrl': 2,
          'type': 3,
          'memberCount': 'four',
          'userRole': 5,
          'muted': 'yes',
          'pinned': 'no',
          'hidden': 1,
          'selfMuted': 0,
        }),
        returnsNormally,
      );
    });

    test('unreadRoomFromJson lastUnreadMessage.isDeleted as string does not '
        'throw', () {
      expect(
        () => RoomMapper.unreadRoomFromJson({
          'roomId': 'r',
          'lastUnreadMessage': {'isDeleted': 'yes'},
        }),
        returnsNormally,
      );
    });

    test('userRoomsFromDto invitedRooms with wrong types does not throw', () {
      expect(
        () => RoomMapper.userRoomsFromDto(
          const UserRoomsDto(
            rooms: [],
            invitedRooms: [
              {'roomId': 42, 'invitedBy': 7, 'roomName': 1},
            ],
          ),
        ),
        returnsNormally,
      );
    });

    test('detailFromDto config.allowInvitations as string does not throw', () {
      expect(
        () => RoomMapper.detailFromDto(
          RoomDetailDto.fromJson({
            'id': 'r',
            'config': {'allowInvitations': 'yes'},
          }),
        ),
        returnsNormally,
      );
    });
  });

  group('UserMapper supplementary fromJson cross-type fuzz', () {
    test('contactFromJson userId as int does not throw', () {
      expect(
        () => UserMapper.contactFromJson({'userId': 42}),
        returnsNormally,
      );
    });

    test('roomUserFromJson userId/role as int does not throw', () {
      expect(
        () => UserMapper.roomUserFromJson({'userId': 42, 'role': 7}),
        returnsNormally,
      );
    });

    test('managedConfigFromJson webhook as non-map does not throw', () {
      expect(
        () => UserMapper.managedConfigFromJson({'webhook': 'not-a-map'}),
        returnsNormally,
      );
    });

    test('managedConfigFromJson webhook.auth fields as wrong types do not '
        'throw', () {
      expect(
        () => UserMapper.managedConfigFromJson({
          'webhook': {
            'url': 7,
            'authMethod': 8,
            'auth': {'username': 9, 'password': 10, 'token': 11},
          },
        }),
        returnsNormally,
      );
    });

    test('fromJsonList with non-map entries drops them', () {
      final users = UserMapper.fromJsonList([
        {'id': 'u1'},
        'not-a-map',
        42,
        null,
        {'id': 'u2'},
      ]);
      expect(users.length, 2);
    });
  });

  group('MessageMapper supplementary fromJson cross-type fuzz', () {
    test('readReceiptFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.readReceiptFromJson({
          'userId': 42,
          'lastReadMessageId': 7,
          'lastReadAt': 8,
          'lastDeliveredMessageId': 9,
          'lastDeliveredAt': 10,
        }),
        returnsNormally,
      );
    });

    test('scheduledFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.scheduledFromJson({
          'id': 1,
          'userId': 2,
          'roomId': 3,
          'sendAt': 4,
          'createdAt': 5,
          'text': 6,
          'metadata': 'not-a-map',
        }),
        returnsNormally,
      );
    });

    test('pinFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.pinFromJson({
          'roomId': 1,
          'messageId': 2,
          'pinnedBy': 3,
          'pinnedAt': 4,
        }),
        returnsNormally,
      );
    });

    test('starredFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.starredFromJson({
          'userId': 1,
          'messageId': 2,
          'roomId': 3,
          'starredAt': 4,
        }),
        returnsNormally,
      );
    });

    test('reportFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.reportFromJson({
          'reporterId': 1,
          'messageId': 2,
          'roomId': 3,
          'reason': 4,
          'reportedAt': 5,
        }),
        returnsNormally,
      );
    });

    test('reactionFromJson with wrong types does not throw', () {
      expect(
        () => MessageMapper.reactionFromJson({
          'emoji': 1,
          'count': 'three',
          'users': [1, 2, 'u3'],
        }),
        returnsNormally,
      );
    });

    test('reactionFromJson users with non-string entries drops them', () {
      final reaction = MessageMapper.reactionFromJson({
        'emoji': '👍',
        'count': 3,
        'users': ['u1', 42, null, 'u2'],
      });
      expect(reaction.users, ['u1', 'u2']);
    });

    test('fromJson metadata.mimeType as int does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 'm',
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
          'metadata': {'mimeType': 42, 'fileName': 7, 'fileSize': 8},
        }),
        returnsNormally,
      );
    });

    test('fromJson inline reaction.reaction/from as int does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 'm',
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
          'reaction': [
            {'reaction': 42, 'from': 7},
          ],
        }),
        returnsNormally,
      );
    });

    test('extractReactions with non-map list entries drops them', () {
      final result = MessageMapper.extractReactions([
        {
          'id': 'm1',
          'reaction': [
            {'reaction': '👍'},
          ],
        },
        'not-a-map',
        42,
      ]);
      expect(result, {
        'm1': {'👍': 1},
      });
    });

    test('extractReactions with id/emoji as int does not throw', () {
      expect(
        () => MessageMapper.extractReactions([
          {
            'id': 42,
            'reaction': [
              {'reaction': 7},
            ],
          },
        ]),
        returnsNormally,
      );
    });

    test('fromJsonList with non-map entries drops them', () {
      final messages = MessageMapper.fromJsonList([
        {'id': 'm1', 'from': 'u', 'timestamp': '2024-01-01T00:00:00Z'},
        'not-a-map',
        42,
        null,
      ]);
      expect(messages.length, 1);
    });
  });

  group('HealthMapper cross-type fuzz', () {
    test('checks as a list does not throw', () {
      expect(
        () => HealthMapper.fromJson({
          'status': 'ok',
          'checks': [1, 2, 3],
        }),
        returnsNormally,
      );
    });

    test('checks as a string does not throw', () {
      expect(
        () => HealthMapper.fromJson({'status': 'ok', 'checks': 'not-a-map'}),
        returnsNormally,
      );
    });
  });
}
