import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomMapper', () {
    test('fromJson maps all fields', () {
      final room = RoomMapper.fromJson({
        'roomId': 'room-1',
        'owner': 'user-1',
        'name': 'Test Room',
        'subject': 'Testing',
        'audience': 'public',
        'allowInvitations': true,
        'members': ['user-1', 'user-2'],
        'publicToken': 'token-123',
        'avatarUrl': 'https://example.com/avatar.png',
        'custom': {'theme': 'dark'},
      });
      expect(room.id, 'room-1');
      expect(room.owner, 'user-1');
      expect(room.name, 'Test Room');
      expect(room.audience, RoomAudience.public);
      expect(room.allowInvitations, isTrue);
      expect(room.members.length, 2);
      expect(room.publicToken, 'token-123');
      expect(room.avatarUrl, 'https://example.com/avatar.png');
    });

    test('detailFromJson maps all fields', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'room-1',
        'name': 'Room',
        'subject': 'Subject',
        'type': 'one-to-one',
        'memberCount': 2,
        'userRole': 'owner',
        'config': {'allowInvitations': true},
        'createdAt': '2024-12-25T20:00:00Z',
        'avatarUrl': 'https://example.com/room.png',
      });
      expect(detail.id, 'room-1');
      expect(detail.type, RoomType.oneToOne);
      expect(detail.memberCount, 2);
      expect(detail.userRole, RoomRole.owner);
      expect(detail.config.allowInvitations, isTrue);
      expect(detail.createdAt, isNotNull);
    });

    test('userRoomsFromJson maps rooms and invited rooms (flat format)', () {
      final userRooms = RoomMapper.userRoomsFromJson({
        'rooms': [
          {
            'roomId': 'r-1',
            'unreadMessages': 5,
            'lastMessage': 'Hello',
            'lastMessageTime': '2024-12-25T20:00:00Z',
            'lastMessageUserId': 'u-1',
          },
        ],
        'invitedRooms': [
          {'roomId': 'r-2', 'invitedBy': 'u-2'},
        ],
        'hasMore': true,
      });
      expect(userRooms.rooms.length, 1);
      expect(userRooms.rooms.first.unreadMessages, 5);
      expect(userRooms.rooms.first.lastMessage, 'Hello');
      expect(
        userRooms.rooms.first.lastMessageTime,
        DateTime.utc(2024, 12, 25, 20),
      );
      expect(userRooms.rooms.first.lastMessageUserId, 'u-1');
      expect(userRooms.invitedRooms.length, 1);
      expect(userRooms.invitedRooms.first.invitedBy, 'u-2');
      expect(userRooms.hasMore, isTrue);
    });

    test('unreadRoomFromJson parses nested lastUnreadMessage from server', () {
      final room = RoomMapper.unreadRoomFromJson({
        'roomId': 'r-1',
        'unreadMessages': 3,
        'lastUnreadMessage': {
          'messageId': 'msg-1',
          'fromJid': 'user-abc',
          'timestamp': '2024-12-25T20:00:00Z',
          'body': 'Hello from server',
          'attachments': [],
          'metadata': {},
          'reaction': [],
        },
      });
      expect(room.roomId, 'r-1');
      expect(room.unreadMessages, 3);
      expect(room.lastMessage, 'Hello from server');
      expect(room.lastMessageTime, DateTime.utc(2024, 12, 25, 20));
      expect(room.lastMessageUserId, 'user-abc');
      expect(room.lastMessageId, 'msg-1');
    });

    test('unreadRoomFromJson handles lastUnreadMessage as 0 (no unreads)', () {
      final room = RoomMapper.unreadRoomFromJson({
        'roomId': 'r-2',
        'unreadMessages': 0,
        'lastUnreadMessage': 0,
      });
      expect(room.roomId, 'r-2');
      expect(room.unreadMessages, 0);
      expect(room.lastMessage, isNull);
      expect(room.lastMessageTime, isNull);
      expect(room.lastMessageUserId, isNull);
      expect(room.lastMessageId, isNull);
    });

    test('unreadRoomFromJson uses text fallback when body is absent', () {
      final room = RoomMapper.unreadRoomFromJson({
        'roomId': 'r-3',
        'unreadMessages': 1,
        'lastUnreadMessage': {
          'messageId': 'msg-2',
          'from': 'user-xyz',
          'timestamp': '2024-12-25T21:00:00Z',
          'text': 'Fallback text',
        },
      });
      expect(room.lastMessage, 'Fallback text');
      expect(room.lastMessageUserId, 'user-xyz');
    });

    test('detailFromJson with null name and subject', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'room-1',
        'type': 'group',
        'memberCount': 5,
        'userRole': 'user',
        'config': {'allowInvitations': false},
      });
      expect(detail.id, 'room-1');
      expect(detail.name, isNull);
      expect(detail.subject, isNull);
      expect(detail.memberCount, 5);
    });

    test('discoveredFromJson maps fields', () {
      final room = RoomMapper.discoveredFromJson({
        'roomId': 'r-1',
        'name': 'Public Room',
        'subject': 'Open',
      });
      expect(room.id, 'r-1');
      expect(room.name, 'Public Room');
    });

    test('detailFromJson maps announcement type', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'room-ann',
        'name': 'Announcements',
        'subject': 'News',
        'type': 'announcement',
        'memberCount': 100,
        'userRole': 'user',
        'config': {'allowInvitations': false},
      });
      expect(detail.id, 'room-ann');
      expect(detail.type, RoomType.announcement);
      expect(detail.memberCount, 100);
      expect(detail.userRole, RoomRole.member);
    });

    test('detailFromJson announcement room isReadOnly for member', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'room-ann',
        'type': 'announcement',
        'memberCount': 50,
        'userRole': 'user',
        'config': {'allowInvitations': false},
      });
      expect(detail.isReadOnly, isTrue);
    });

    test('detailFromJson announcement room not readOnly for owner', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'room-ann',
        'type': 'announcement',
        'memberCount': 50,
        'userRole': 'owner',
        'config': {'allowInvitations': false},
      });
      expect(detail.isReadOnly, isFalse);
    });
  });
}
