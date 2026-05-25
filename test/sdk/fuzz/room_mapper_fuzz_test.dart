import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';

void main() {
  group('RoomMapper.fromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'roomId': null},
      {'roomId': ''},
      {'id': 'r'},
      {'roomId': 'r', 'audience': 'unknown'},
      {'roomId': 'r', 'audience': ''},
      {'roomId': 'r', 'members': <dynamic>[]},
      {'roomId': 'r', 'members': null},
      {'roomId': 'r', 'allowInvitations': null},
      {'roomId': 'r', 'name': '<script>alert(1)</script>'},
      {'roomId': 'r', 'name': 'a' * 100000},
      {'roomId': 'r', 'subject': '\u202E\u202D\u200B'},
      {'roomId': 'r', 'custom': <String, dynamic>{}},
      {
        'roomId': 'r',
        'custom': <String, dynamic>{for (var i = 0; i < 50; i++) 'k$i': i},
      },
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => RoomMapper.fromJson(inputs[i]), returnsNormally);
      });
    }

    test('output is always a ChatRoom', () {
      for (final input in inputs) {
        expect(RoomMapper.fromJson(input), isA<ChatRoom>());
      }
    });
  });

  group('RoomMapper.detailFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'id': null},
      {'id': '', 'type': 'unknown'},
      {'id': 'r', 'type': ''},
      {'id': 'r', 'type': 'group', 'memberCount': null},
      {'id': 'r', 'type': 'one-to-one', 'userRole': 'unknown'},
      {'id': 'r', 'type': 'announcement'},
      {'id': 'r', 'createdAt': 'not-a-date'},
      {'id': 'r', 'createdAt': null},
      {'id': 'r', 'config': <String, dynamic>{}},
      {
        'id': 'r',
        'config': {'allowInvitations': null},
      },
      {'id': 'r', 'muted': null, 'pinned': null, 'hidden': null},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => RoomMapper.detailFromJson(inputs[i]), returnsNormally);
      });
    }
  });

  group('RoomMapper.discoveredFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'roomId': null},
      {'roomId': 'r', 'memberCount': null},
      {'id': 'r', 'name': '', 'subject': null, 'avatarUrl': null},
      {'roomId': 'r', 'custom': null},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => RoomMapper.discoveredFromJson(inputs[i]), returnsNormally);
      });
    }
  });

  group('RoomMapper.unreadRoomFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'roomId': null},
      {'roomId': 'r'},
      {'roomId': 'r', 'unreadMessages': null},
      {'roomId': 'r', 'lastUnreadMessage': <String, dynamic>{}},
      {
        'roomId': 'r',
        'lastUnreadMessage': {
          'body': '',
          'timestamp': 'not-a-date',
          'fromJid': null,
          'messageId': null,
        },
      },
      {
        'roomId': 'r',
        'lastUnreadMessage': {
          'text': 'hello',
          'timestamp': null,
          'from': 'u',
          'id': 'm',
          'messageType': 'unknown',
          'metadata': {'duration': 'not-a-num'},
          'isDeleted': null,
        },
      },
      {
        'roomId': 'r',
        'lastUnreadMessage': {'metadata': <String, dynamic>{}},
      },
      {
        'roomId': 'r',
        'lastMessageTime': 'not-a-date',
        'lastMessageReceipt': 'unknown',
        'lastMessageType': 'unknown',
        'lastMessageDurationMs': null,
      },
      {'roomId': 'r', 'userRole': 'unknown'},
      {'roomId': 'r', 'muted': null, 'pinned': null, 'hidden': null},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => RoomMapper.unreadRoomFromJson(inputs[i]), returnsNormally);
      });
    }
  });

  group('RoomMapper fuzz — random property-based', () {
    final random = Random(8888);

    String randomString(int len) {
      const chars =
          'abcdefghijklmnopqrstuvwxyz0123456789-_:;"\'{}[]\u200B\u202E ';
      final buf = StringBuffer();
      for (var i = 0; i < len; i++) {
        buf.write(chars[random.nextInt(chars.length)]);
      }
      return buf.toString();
    }

    test('100 random ChatRoom inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'roomId': random.nextBool() ? randomString(8) : null,
          'name': random.nextBool() ? randomString(20) : null,
          'subject': random.nextBool() ? randomString(40) : null,
          'audience': [
            'public',
            'unrestricted',
            'contacts',
            randomString(6),
          ][random.nextInt(4)],
          'allowInvitations': random.nextBool(),
          'members': <String>[for (var j = 0; j < 3; j++) randomString(5)],
          'avatarUrl': random.nextBool() ? randomString(40) : null,
        };
        expect(
          () => RoomMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test('100 random unreadRoom inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'roomId': randomString(8),
          'unreadMessages': random.nextInt(10000),
          'lastMessage': random.nextBool() ? randomString(40) : null,
          'lastMessageTime': randomString(20),
          'lastMessageType': randomString(8),
          'lastMessageReceipt': randomString(8),
          'lastMessageDurationMs': random.nextInt(1 << 20),
          'lastMessageIsDeleted': random.nextBool(),
          'muted': random.nextBool(),
          'pinned': random.nextBool(),
          'hidden': random.nextBool(),
          'userRole': randomString(6),
        };
        expect(
          () => RoomMapper.unreadRoomFromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });
  });
}
