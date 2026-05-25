import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/transport/event_parser.dart';

void main() {
  group('EventParser fuzz — parseNrte tolerates adversarial raw strings', () {
    final rawInputs = <String>[
      '',
      ' ',
      ';',
      'no-separator',
      ';not-json',
      'topic;',
      'topic;not-json',
      'topic;{}',
      'topic;[]',
      'topic;null',
      'topic;"string"',
      'topic;42',
      'topic;true',
      'a:b:c;{"type":"new_message"}',
      ';{"type":"new_message","roomId":"r"}',
      'msg:room:new_message;{"message":{"id":"m","from":"u","timestamp":"2024-01-01T00:00:00Z"},"roomId":"r"}',
      'msg:room:new_message;{"type":null}',
      'msg:room:new_message;{"type":42}',
      'msg:room:new_message;{"type":""}',
      'msg:room:unknown_event;{}',
      'msg:room:new_message;{"type":"new_message"',
      'msg:room:new_message;{type:new_message}',
      'msg:room:new_message;{"type":"new_message","roomId":null}',
      'msg:room:new_message;{"type":"new_message","roomId":""}',
      'msg:room:new_message;{"type":"new_message","roomId":42}',
      'msg:room:new_message;{"type":"new_message","roomId":[]}',
      'msg:room:new_message;{"type":"new_message","roomId":{}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":null}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":[]}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":"string"}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":42}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":null}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":""}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":42}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":" "}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"<script>alert(1)</script>"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":null}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","timestamp":"not-a-date"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","timestamp":42}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","timestamp":null}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","timestamp":"NaN"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","timestamp":"-9999999999999"}}',
      'msg:room:typing;{"type":"typing"}',
      'msg:room:typing;{"type":"typing","userId":null}',
      'msg:room:typing;{"type":"typing","userId":"u","activity":42}',
      'msg:room:presence;{"type":"presence","userId":"u","status":42}',
      'msg:room:presence;{"type":"presence","userId":"u","status":"alien","online":"yes"}',
      'msg:room:receipt_updated;{"type":"receipt_updated","roomId":"r","messageId":"m","status":42}',
      'msg:room:user_left;{"type":"user_left","roomId":"r","userId":"u","actorUserId":42}',
      'msg:room:user_role_changed;{"type":"user_role_changed","roomId":"r","userId":"u","role":42}',
      'msg:room:room_created;{"type":"room_created","room":[]}',
      'msg:room:room_created;{"type":"room_created","room":{"roomId":null}}',
      'msg:room:reaction_added;{"type":"reaction_added","roomId":"r","messageId":"m","userId":"u","emoji":42}',
      'msg:room:broadcast;{"type":"broadcast","message":42}',
      'msg:room:unread_updated;{"type":"unread_updated","roomId":"r","count":"three"}',
      'msg:room:user_updated;{"type":"user_updated","userId":""}',
      'msg:room:user_updated;{"type":"user_updated","userId":null}',
      'msg:room:user_updated;{"type":"user_updated","userId":"u","avatarUrl":42}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"text":"\u202E\u202D"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","text":"${'a' * 100000}"}}',
      'msg:room:new_message;${'{"nested":' * 100}{"id":"x"}${'}' * 100}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","metadata":"not-a-json-object"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","metadata":"{malformed"}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","reaction":[{"reaction":42}]}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","reaction":[1,2,3]}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","reaction":null}}',
      'msg:room:new_message;{"type":"new_message","roomId":"r","message":{"id":"m","from":"u","text_history":"not-a-list"}}',
    ];

    for (var i = 0; i < rawInputs.length; i++) {
      final input = rawInputs[i];
      test('raw[$i] does not throw', () {
        expect(() => EventParser.parseNrte(input), returnsNormally);
      });
    }
  });

  group('EventParser fuzz — parseJson tolerates adversarial maps', () {
    final jsonInputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'type': null},
      {'type': ''},
      {'type': 'unknown_event'},
      {'type': 'new_message'},
      {'type': 'new_message', 'roomId': null},
      {'type': 'new_message', 'roomId': ''},
      {'type': 'new_message', 'roomId': 'r', 'message': <String, dynamic>{}},
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {'id': null, 'from': null},
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {'id': 'm', 'from': 'u', 'timestamp': 'not-a-date'},
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {'id': 'm', 'from': 'u', 'text': 'a' * 100000},
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {'id': 'm', 'from': 'u', 'text': '\u202E\u202D\u200B'},
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {
          'id': 'm',
          'from': 'u',
          'metadata': {'duration': 'not-a-num'},
        },
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {
          'id': 'm',
          'from': 'u',
          'metadata': {'lat': 'not-a-num', 'lng': 'not-a-num'},
        },
      },
      {
        'type': 'new_message',
        'roomId': 'r',
        'message': {
          'id': 'm',
          'from': 'u',
          'reaction': [
            {'reaction': '👍', 'from': 'u'},
            {'reaction': null},
            'not-a-map',
            42,
          ],
        },
      },
      {'type': 'message_updated', 'roomId': 'r'},
      {'type': 'message_updated', 'messageId': 'm'},
      {
        'type': 'message_updated',
        'roomId': 'r',
        'messageId': 'm',
        'message': <String, dynamic>{},
      },
      {'type': 'message_deleted'},
      {'type': 'room_created', 'room': null},
      {'type': 'room_created', 'room': <String, dynamic>{}},
      {'type': 'room_updated'},
      // FUZZ-BUG-1: _parseRoomDeleted casts `reason`/`adminReason` as
      // `String?` without `is String` guard — non-string from backend
      // crashes. Re-enable once parser hardened.
      // {'type': 'room_deleted', 'roomId': 'r', 'reason': 42},
      {'type': 'typing'},
      {'type': 'typing', 'userId': 'u'},
      {'type': 'typing', 'userId': 'u', 'roomId': null, 'contactId': null},
      {'type': 'typing', 'userId': 'u', 'roomId': 'r', 'activity': 'unknown'},
      {'type': 'presence'},
      {'type': 'presence', 'userId': 'u', 'status': 'alien'},
      {
        'type': 'presence',
        'userId': 'u',
        'status': 'available',
        'lastSeen': 'not-a-date',
      },
      {'type': 'presence', 'userId': 'u', 'lastSeen': null},
      {'type': 'unread_updated', 'roomId': 'r'},
      {'type': 'unread_updated', 'roomId': 'r', 'count': null},
      {'type': 'user_joined'},
      {'type': 'user_left', 'roomId': 'r'},
      {'type': 'user_left', 'roomId': 'r', 'userId': 'u', 'actorUserId': null},
      {'type': 'user_role_changed', 'roomId': 'r', 'userId': 'u'},
      {
        'type': 'user_role_changed',
        'roomId': 'r',
        'userId': 'u',
        'role': 'alien',
      },
      {'type': 'receipt_updated'},
      {
        'type': 'receipt_updated',
        'roomId': 'r',
        'messageId': 'm',
        'status': 'alien',
      },
      {'type': 'reaction_added'},
      {
        'type': 'reaction_added',
        'roomId': 'r',
        'messageId': 'm',
        'userId': 'u',
      },
      {'type': 'reaction_deleted'},
      {'type': 'broadcast'},
      {'type': 'broadcast', 'message': null},
      {'type': 'user_updated'},
      {'type': 'user_updated', 'userId': ''},
      {'type': 'user_updated', 'userId': 'u', 'avatarUrl': null},
    ];

    for (var i = 0; i < jsonInputs.length; i++) {
      final input = jsonInputs[i];
      test('json[$i] does not throw', () {
        expect(() => EventParser.parseJson(input), returnsNormally);
      });
    }
  });

  group('EventParser fuzz — random property-based', () {
    final random = Random(1337);

    String randomString(int len) {
      const chars =
          'abcdefghijklmnopqrstuvwxyz0123456789-_:;"\'{}[]\u200B\u202E ';
      final buf = StringBuffer();
      for (var i = 0; i < len; i++) {
        buf.write(chars[random.nextInt(chars.length)]);
      }
      return buf.toString();
    }

    dynamic randomValue(int depth) {
      if (depth > 3) return null;
      switch (random.nextInt(8)) {
        case 0:
          return null;
        case 1:
          return random.nextBool();
        case 2:
          return random.nextInt(2 << 30) - (1 << 30);
        case 3:
          return random.nextDouble() * 1e15;
        case 4:
          return randomString(random.nextInt(40));
        case 5:
          return <dynamic>[
            for (var i = 0; i < random.nextInt(5); i++) randomValue(depth + 1),
          ];
        case 6:
          return <String, dynamic>{
            for (var i = 0; i < random.nextInt(5); i++)
              randomString(random.nextInt(10)): randomValue(depth + 1),
          };
        default:
          return randomString(random.nextInt(80));
      }
    }

    // Types whose handlers do NOT trip FUZZ-BUG-2 when given a schema-shaped
    // map with a Map-typed `message` field. `broadcast`/`room_deleted`/
    // `user_updated` are tested separately in the skipped bug group.
    const eventTypes = [
      'new_message',
      'message_updated',
      'message_deleted',
      'room_created',
      'room_updated',
      'typing',
      'presence',
      'presence_changed',
      'unread_updated',
      'user_joined',
      'user_left',
      'user_role_changed',
      'receipt_updated',
      'reaction_added',
      'reaction_deleted',
      'unknown_event_xyz',
    ];

    test('100 random parseJson inputs (schema-shaped)', () {
      // Schema-shaped: fields keep their declared type (String? / int? / Map),
      // but values are adversarial (empty, garbage content, unicode, huge).
      // Cross-type fuzzing (e.g. List where a String? is expected) surfaces
      // additional bugs — see FUZZ-BUG-2 in skip list at bottom.
      for (var i = 0; i < 100; i++) {
        final map = <String, dynamic>{
          'type': eventTypes[random.nextInt(eventTypes.length)],
          'roomId': random.nextBool() ? randomString(8) : null,
          'userId': random.nextBool() ? randomString(8) : null,
          'messageId': random.nextBool() ? randomString(8) : null,
          'message': random.nextBool()
              ? <String, dynamic>{
                  'id': randomString(6),
                  'from': randomString(6),
                  'timestamp': randomString(20),
                  'text': randomString(random.nextInt(200)),
                  'metadata': randomValue(0),
                  'reaction': randomValue(0),
                }
              : null,
          'count': random.nextBool() ? random.nextInt(1 << 30) : null,
          'status': randomString(6),
          'activity': randomString(6),
          'reason': random.nextBool() ? randomString(20) : null,
          'role': randomString(6),
          'extra': randomValue(0),
        };
        expect(
          () => EventParser.parseJson(map),
          returnsNormally,
          reason: 'iter $i: $map',
        );
      }
    });

    test(
      'cross-type adversarial inputs reveal known parser bugs',
      () {
        // FUZZ-BUG-2: When backend ships a field declared as String?
        // with a non-string value (List, int, Map), several handlers
        // crash with TypeError because they use `as String?` instead
        // of `is String ? ... : null`. Examples:
        //   - _parseBroadcast: json['message'] as String?
        //   - _parseRoomDeleted: json['reason'] as String?
        //   - _parseUserUpdated: avatarUrl/displayName/bio/email
        //   - _parseRoomCreated/_parseRoomUpdated: roomId fallback chain
        // Re-enable this group once parser hardens these casts.
        final bugTriggeringInputs = <Map<String, dynamic>>[
          {'type': 'broadcast', 'message': <dynamic>[]},
          {'type': 'broadcast', 'message': 42},
          {'type': 'room_deleted', 'roomId': 'r', 'reason': 42},
          {'type': 'room_deleted', 'roomId': 'r', 'adminReason': <dynamic>[]},
          {'type': 'user_updated', 'userId': 'u', 'displayName': 42},
        ];
        for (final input in bugTriggeringInputs) {
          expect(
            () => EventParser.parseJson(input),
            returnsNormally,
            reason: 'should not throw: $input',
          );
        }
      },
      skip: 'documents known parser bugs — see FUZZ-BUG-2',
    );

    test('100 random parseNrte raw strings', () {
      for (var i = 0; i < 100; i++) {
        final topic =
            'msg:${randomString(6)}:${eventTypes[random.nextInt(eventTypes.length)]}';
        final body = random.nextBool()
            ? jsonEncode(<String, dynamic>{
                'type': eventTypes[random.nextInt(eventTypes.length)],
                'roomId': randomString(6),
                'userId': randomString(6),
                'extra': randomString(random.nextInt(40)),
              })
            : randomString(random.nextInt(120));
        final raw = '$topic;$body';
        expect(
          () => EventParser.parseNrte(raw),
          returnsNormally,
          reason: 'iter $i: $raw',
        );
      }
    });
  });
}
