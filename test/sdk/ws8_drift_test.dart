import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
import 'package:noma_chat/src/_internal/transport/event_parser.dart';

void main() {
  group('RoomMapper drift', () {
    test('reaction array on last message yields the latest emoji', () {
      final ur = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 1,
        'lastUnreadMessage': {
          'reaction': [
            {'from': 'u2', 'reaction': '👍', 'time': '2026-06-15T10:00:00Z'},
            {'from': 'u3', 'reaction': '❤️', 'time': '2026-06-15T10:00:01Z'},
          ],
        },
      });
      expect(ur.lastMessageReactionEmoji, '❤️');
    });

    test('reaction as plain string is still supported', () {
      final ur = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 1,
        'lastUnreadMessage': {'reaction': '🔥'},
      });
      expect(ur.lastMessageReactionEmoji, '🔥');
    });

    test('location messageType parses in the preview', () {
      final ur = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 1,
        'lastUnreadMessage': {'messageType': 'location'},
      });
      expect(ur.lastMessageType, MessageType.location);
    });

    test('selfMuted maps from the listing', () {
      final ur = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
        'selfMuted': true,
      });
      expect(ur.selfMuted, isTrue);
    });

    test('InvitedRoom carries roomName/subject/roomType', () {
      final rooms = RoomMapper.userRoomsFromJson({
        'rooms': <dynamic>[],
        'invitedRooms': [
          {
            'roomId': 'r2',
            'invitedBy': 'u1',
            'roomName': 'Team',
            'subject': 'Welcome',
            'roomType': 'group',
          },
        ],
      });
      final invited = rooms.invitedRooms.single;
      expect(invited.roomId, 'r2');
      expect(invited.roomName, 'Team');
      expect(invited.subject, 'Welcome');
      expect(invited.roomType, 'group');
    });
  });

  group('EventParser drift', () {
    test('broadcast carries fromUserId when present', () {
      final event = EventParser.parseJson({
        'type': 'broadcast',
        'message': 'maintenance at 3am',
        'fromUserId': 'admin-1',
      });
      expect(event, isA<BroadcastEvent>());
      expect((event! as BroadcastEvent).fromUserId, 'admin-1');
    });

    test('broadcast without fromUserId is still parsed', () {
      final event = EventParser.parseJson({
        'type': 'broadcast',
        'message': 'hi',
      });
      expect(event, isA<BroadcastEvent>());
      expect((event! as BroadcastEvent).fromUserId, isNull);
    });
  });
}
