import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';
import 'package:noma_chat/src/cache/serialization.dart';

void main() {
  group('UnreadRoom — mentions + muteUntil parsing', () {
    test('unreadRoomFromJson reads unreadMentions and muteUntil', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 5,
        'unreadMentions': 2,
        'muteUntil': '2026-06-15T18:00:00Z',
      });
      expect(unread.unreadMessages, 5);
      expect(unread.unreadMentions, 2);
      expect(unread.muteUntil, DateTime.utc(2026, 6, 15, 18));
    });

    test('unreadRoomFromJson defaults mentions to 0 and muteUntil to null', () {
      final unread = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 0,
      });
      expect(unread.unreadMentions, 0);
      expect(unread.muteUntil, isNull);
    });
  });

  group('UnreadRoom — cache round-trip preserves new fields', () {
    test('toMap/fromMap keep unreadMentions and muteUntil', () {
      final original = RoomMapper.unreadRoomFromJson({
        'roomId': 'r1',
        'unreadMessages': 3,
        'unreadMentions': 1,
        'muteUntil': '2026-06-15T18:00:00Z',
      });
      final restored = unreadRoomFromMap(unreadRoomToMap(original));
      expect(restored.unreadMentions, 1);
      expect(restored.muteUntil, DateTime.utc(2026, 6, 15, 18));
    });
  });

  group('RoomDetail — muteUntil parsing', () {
    test('detailFromJson reads muteUntil', () {
      final detail = RoomMapper.detailFromJson({
        'id': 'r1',
        'type': 'group',
        'memberCount': 3,
        'userRole': 'user',
        'muted': true,
        'muteUntil': '2026-06-15T18:00:00Z',
      });
      expect(detail.muteUntil, DateTime.utc(2026, 6, 15, 18));
    });
  });

  group('StarredMessage — mapping', () {
    test('starredFromJson maps ids and timestamp', () {
      final starred = MessageMapper.starredFromJson({
        'userId': 'me',
        'messageId': 'm1',
        'roomId': 'r1',
        'starredAt': '2026-06-15T10:00:00Z',
      });
      expect(starred.userId, 'me');
      expect(starred.messageId, 'm1');
      expect(starred.roomId, 'r1');
      expect(starred.starredAt, DateTime.utc(2026, 6, 15, 10));
    });

    test('StarredMessage has value equality / hashCode / toString', () {
      final at = DateTime.utc(2026, 6, 15, 10);
      final a = StarredMessage(
        userId: 'me',
        messageId: 'm1',
        roomId: 'r1',
        starredAt: at,
      );
      final b = StarredMessage(
        userId: 'me',
        messageId: 'm1',
        roomId: 'r1',
        starredAt: at,
      );
      final c = StarredMessage(
        userId: 'me',
        messageId: 'm2',
        roomId: 'r1',
        starredAt: at,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('m1'));
    });
  });
}
