import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/user_mapper.dart';

void main() {
  group('UserMapper.fromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'id': null},
      {'id': ''},
      {'userId': 'u'},
      {'id': 'u', 'role': 'unknown'},
      {'id': 'u', 'role': ''},
      {'id': 'u', 'active': null},
      {'id': 'u', 'displayName': '<script>alert(1)</script>'},
      {'id': 'u', 'displayName': 'a' * 100000},
      {'id': 'u', 'bio': '\u202E\u202D\u200B'},
      {'id': 'u', 'avatarUrl': ' '},
      {'id': 'u', 'custom': <String, dynamic>{}},
      {'id': 'u', 'custom': null},
      {'id': 'u', 'configuration': null},
      {'id': 'u', 'configuration': <String, dynamic>{}},
      {
        'id': 'u',
        'configuration': {'metadata': null, 'webhook': null},
      },
      {
        'id': 'u',
        'configuration': {'webhook': <String, dynamic>{}},
      },
      {
        'id': 'u',
        'configuration': {
          'webhook': {'url': null, 'auth': <String, dynamic>{}},
        },
      },
      {
        'id': 'u',
        'configuration': {
          'webhook': {
            'url': '',
            'auth': {'type': 'unknown', 'token': null},
          },
        },
      },
      {
        'id': 'u',
        'configuration': {
          'webhook': {
            'url': 'https://example.com',
            'auth': {'type': 'basic', 'username': 'u', 'password': 'p'},
          },
        },
      },
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => UserMapper.fromJson(inputs[i]), returnsNormally);
      });
    }

    test('output is always a ChatUser', () {
      for (final input in inputs) {
        expect(UserMapper.fromJson(input), isA<ChatUser>());
      }
    });
  });

  group('UserMapper.contactFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'jid': null},
      {'userId': null, 'id': null},
      {'jid': ''},
      {'jid': 'u'},
      {'userId': 'u'},
      {'id': 'u'},
      {'jid': 'a' * 10000},
      {'jid': '<script>alert(1)</script>'},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => UserMapper.contactFromJson(inputs[i]), returnsNormally);
      });
    }

    test('userId as int is coerced to string, not dropped to empty', () {
      final contact = UserMapper.contactFromJson({'userId': 42});
      expect(contact.userId, '42');
    });
  });

  group('UserMapper.roomUserFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'userId': null},
      {'userId': '', 'userRole': 'unknown'},
      {'userId': 'u', 'userRole': null},
      {'userId': 'u', 'role': 'unknown'},
      {'userId': 'u', 'role': 'admin'},
      {'userId': 'u', 'userRole': 'owner'},
      {'userId': 'u', 'userRole': 'member'},
      {'userId': 'u', 'role': '<script>'},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => UserMapper.roomUserFromJson(inputs[i]), returnsNormally);
      });
    }

    test('userId as int is coerced to string, not dropped to empty', () {
      final user = UserMapper.roomUserFromJson({'userId': 42, 'role': 7});
      expect(user.userId, '42');
    });
  });

  group('UserMapper.managedConfigFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'metadata': null, 'webhook': null},
      {'metadata': <String, dynamic>{}, 'webhook': <String, dynamic>{}},
      {
        'webhook': {'url': null, 'auth': null},
      },
      {
        'webhook': {
          'url': '',
          'auth': {'type': 'bearer', 'token': null},
        },
      },
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(
          () => UserMapper.managedConfigFromJson(inputs[i]),
          returnsNormally,
        );
      });
    }
  });

  group('UserMapper fuzz — random property-based', () {
    final random = Random(1234);

    String randomString(int len) {
      const chars =
          'abcdefghijklmnopqrstuvwxyz0123456789-_:;"\'{}[]\u200B\u202E ';
      final buf = StringBuffer();
      for (var i = 0; i < len; i++) {
        buf.write(chars[random.nextInt(chars.length)]);
      }
      return buf.toString();
    }

    test('100 random ChatUser inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'id': random.nextBool() ? randomString(8) : null,
          'displayName': random.nextBool() ? randomString(20) : null,
          'avatarUrl': random.nextBool() ? randomString(40) : null,
          'bio': random.nextBool() ? randomString(80) : null,
          'email': random.nextBool() ? randomString(30) : null,
          'role': randomString(6),
          'active': random.nextBool(),
        };
        expect(
          () => UserMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test('100 random contact inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'jid': random.nextBool() ? randomString(8) : null,
          'userId': random.nextBool() ? randomString(8) : null,
          'id': random.nextBool() ? randomString(8) : null,
        };
        expect(
          () => UserMapper.contactFromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });
  });
}
