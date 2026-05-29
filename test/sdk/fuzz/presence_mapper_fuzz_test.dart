import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/presence_mapper.dart';

void main() {
  group('PresenceMapper.fromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'userId': null},
      {'userId': ''},
      {'userId': 'u'},
      {'userId': 'u', 'status': null},
      {'userId': 'u', 'status': ''},
      {'userId': 'u', 'status': 'alien'},
      {'userId': 'u', 'status': 'available', 'online': null},
      {'userId': 'u', 'status': 'available', 'lastSeen': 'not-a-date'},
      {'userId': 'u', 'status': 'away', 'lastSeen': null},
      {'userId': 'u', 'status': 'busy', 'lastSeen': ''},
      {'userId': 'u', 'status': 'dnd', 'lastSeen': '9999-99-99T99:99:99Z'},
      {
        'userId': 'u',
        'status': 'offline',
        'statusText': '<script>alert(1)</script>',
      },
      {
        'userId': 'u',
        'status': 'available',
        'statusText': '\u202E\u202D\u200B',
      },
      {'userId': 'u', 'status': 'available', 'statusText': 'a' * 100000},
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => PresenceMapper.fromJson(inputs[i]), returnsNormally);
      });
    }

    test('output is always a ChatPresence', () {
      for (final input in inputs) {
        expect(PresenceMapper.fromJson(input), isA<ChatPresence>());
      }
    });

    test('unknown status defaults to offline', () {
      final presence = PresenceMapper.fromJson({
        'userId': 'u',
        'status': 'alien',
      });
      expect(presence.status, PresenceStatus.offline);
    });
  });

  group('PresenceMapper.bulkFromJson fuzz', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'userId': 'u'},
      {'own': null, 'contacts': null},
      {'own': <String, dynamic>{}, 'contacts': <dynamic>[]},
      {
        'own': {'userId': 'u', 'status': 'available'},
        'contacts': <dynamic>[],
      },
      {
        'own': {'userId': 'u'},
        'contacts': [
          {'userId': 'c1', 'status': 'away'},
          {'userId': null, 'status': null},
          <String, dynamic>{},
        ],
      },
      {
        'own': {'userId': null, 'status': null},
        'contacts': <dynamic>[],
      },
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => PresenceMapper.bulkFromJson(inputs[i]), returnsNormally);
      });
    }
  });

  group('PresenceMapper fuzz — random property-based', () {
    final random = Random(7777);

    String randomString(int len) {
      const chars =
          'abcdefghijklmnopqrstuvwxyz0123456789-_:;"\'{}[]\u200B\u202E ';
      final buf = StringBuffer();
      for (var i = 0; i < len; i++) {
        buf.write(chars[random.nextInt(chars.length)]);
      }
      return buf.toString();
    }

    test('100 random presence inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'userId': random.nextBool() ? randomString(8) : null,
          'status': [
            'available',
            'away',
            'busy',
            'dnd',
            'offline',
            randomString(6),
          ][random.nextInt(6)],
          'online': random.nextBool(),
          'statusText': random.nextBool() ? randomString(40) : null,
          'lastSeen': random.nextBool() ? randomString(20) : null,
        };
        expect(
          () => PresenceMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test('100 random bulk inputs', () {
      for (var i = 0; i < 100; i++) {
        final ownData = random.nextBool()
            ? <String, dynamic>{
                'userId': randomString(6),
                'status': randomString(6),
                'online': random.nextBool(),
              }
            : null;
        final contacts = <dynamic>[
          for (var j = 0; j < random.nextInt(5); j++)
            <String, dynamic>{
              'userId': randomString(6),
              'status': randomString(6),
              'online': random.nextBool(),
            },
        ];
        final json = <String, dynamic>{
          if (ownData != null) 'own': ownData,
          if (random.nextBool()) 'contacts': contacts,
          'userId': randomString(6),
          'status': randomString(6),
          'online': random.nextBool(),
        };
        expect(
          () => PresenceMapper.bulkFromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });
  });
}
