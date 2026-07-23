import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';

void main() {
  group('MessageMapper.fromJson fuzz — does not throw on garbage JSON', () {
    final inputs = <Map<String, dynamic>>[
      <String, dynamic>{},
      {'id': null, 'from': null, 'timestamp': null},
      {'id': '', 'from': '', 'timestamp': ''},
      {'id': 'm', 'from': 'u', 'timestamp': 'not-a-date'},
      {'id': 'm', 'from': 'u', 'timestamp': 'NaN'},
      {'id': 'm', 'from': 'u', 'timestamp': '-9999999999999'},
      {'id': 'm', 'from': 'u', 'timestamp': '9999-99-99T99:99:99Z'},
      {'id': 'm', 'from': 'u', 'timestamp': ''},
      {'id': 'm', 'from': 'u', 'timestamp': ' '},
      {'id': 'm', 'from': 'u', 'timestamp': '2024-01-01T00:00:00Z'},
      {'id': 'm', 'from': 'u', 'timestamp': '2024-01-01T00:00:00Z', 'text': ''},
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': ' ',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': '<script>alert(1)</script>',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': '\u202E\u202D\u200B',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': 'a' * 100000,
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'unknown_type',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': '',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'receipt': 'unknown',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': <String, dynamic>{},
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {'edited': 'not-a-bool'},
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {'lat': 'not-a-num', 'lng': 'not-a-num'},
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {'lat': 1.0, 'lng': 2.0},
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': 'not-a-map',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': '{malformed',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': '',
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'reaction': <dynamic>[],
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'reaction': [
          {'reaction': '👍', 'from': 'u'},
          {'emoji': '🚀', 'from': null},
          {'reaction': null},
          'not-a-map',
          42,
        ],
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text_history': <dynamic>[],
      },
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'text_history': [
          {'text': 'old'},
        ],
      },
      // Server field names
      {
        'messageId': 'm',
        'fromJid': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'body': 'hello',
      },
      // Deeply nested metadata
      {
        'id': 'm',
        'from': 'u',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': <String, dynamic>{for (var i = 0; i < 100; i++) 'k$i': i},
      },
    ];

    for (var i = 0; i < inputs.length; i++) {
      test('input[$i] does not throw', () {
        expect(() => MessageMapper.fromJson(inputs[i]), returnsNormally);
      });
    }

    test('null timestamp defaults to DateTime.now() (not epoch)', () {
      final before = DateTime.now();
      final msg = MessageMapper.fromJson({
        'id': 'm',
        'from': 'u',
        'timestamp': null,
      });
      final after = DateTime.now();
      expect(
        msg.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
        reason: 'timestamp should not be epoch 1970',
      );
      expect(
        msg.timestamp.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(msg.timestamp.year, greaterThan(2020));
    });

    test('invalid timestamp defaults to DateTime.now() (not epoch)', () {
      final msg = MessageMapper.fromJson({
        'id': 'm',
        'from': 'u',
        'timestamp': 'not-a-date',
      });
      expect(msg.timestamp.year, greaterThan(2020));
    });

    test('output is always a ChatMessage (no exceptions, no nulls)', () {
      for (final input in inputs) {
        final msg = MessageMapper.fromJson(input);
        expect(msg, isA<ChatMessage>());
      }
    });
  });

  group('MessageMapper.fromJsonList fuzz', () {
    test('handles malformed entries', () {
      final list = <dynamic>[
        <String, dynamic>{'id': 'm1', 'from': 'u', 'timestamp': ''},
        <String, dynamic>{},
        <String, dynamic>{'id': null, 'from': null, 'timestamp': null},
      ];
      expect(() => MessageMapper.fromJsonList(list), returnsNormally);
    });
  });

  group('MessageMapper.extractReactions fuzz', () {
    test('handles garbage list', () {
      final list = <dynamic>[
        <String, dynamic>{
          'id': 'm1',
          'reaction': [
            {'reaction': '👍'},
            'not-a-map',
            <String, dynamic>{'emoji': null},
            42,
          ],
        },
        <String, dynamic>{'id': '', 'reaction': <dynamic>[]},
        <String, dynamic>{'id': 'm2'},
        <String, dynamic>{'id': 'm3', 'reaction': 'not-a-list'},
      ];
      expect(() => MessageMapper.extractReactions(list), returnsNormally);
    });

    test('id as int is coerced to string, not dropped to empty', () {
      final result = MessageMapper.extractReactions([
        {
          'id': 42,
          'reaction': [
            {'reaction': '👍'},
          ],
        },
      ]);
      expect(result.containsKey('42'), isTrue);
      expect(result.containsKey(''), isFalse);
    });
  });

  group('MessageMapper supplementary fromJsons fuzz', () {
    test('readReceiptFromJson tolerates garbage', () {
      final inputs = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'userId': null},
        {'userId': '', 'lastReadAt': 'not-a-date'},
        {'userId': 'u', 'lastReadMessageId': 'm', 'lastReadAt': null},
      ];
      for (final input in inputs) {
        expect(() => MessageMapper.readReceiptFromJson(input), returnsNormally);
      }
    });

    test('readReceiptFromJson userId as int is coerced, not dropped to '
        'empty', () {
      final receipt = MessageMapper.readReceiptFromJson({'userId': 42});
      expect(receipt.userId, '42');
    });

    test('scheduledFromJson tolerates garbage', () {
      final inputs = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'id': null, 'userId': null, 'roomId': null},
        {'sendAt': 'not-a-date', 'createdAt': 'not-a-date'},
      ];
      for (final input in inputs) {
        expect(() => MessageMapper.scheduledFromJson(input), returnsNormally);
      }
    });

    test('scheduledFromJson id/userId/roomId as int are coerced, not '
        'dropped to empty', () {
      final scheduled = MessageMapper.scheduledFromJson({
        'id': 1,
        'userId': 2,
        'roomId': 3,
      });
      expect(scheduled.id, '1');
      expect(scheduled.userId, '2');
      expect(scheduled.roomId, '3');
    });

    test('pinFromJson tolerates garbage', () {
      final inputs = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'pinnedAt': 'not-a-date'},
      ];
      for (final input in inputs) {
        expect(() => MessageMapper.pinFromJson(input), returnsNormally);
      }
    });

    test('pinFromJson roomId/messageId/pinnedBy as int are coerced, not '
        'dropped to empty', () {
      final pin = MessageMapper.pinFromJson({
        'roomId': 1,
        'messageId': 2,
        'pinnedBy': 3,
      });
      expect(pin.roomId, '1');
      expect(pin.messageId, '2');
      expect(pin.pinnedBy, '3');
    });

    test('starredFromJson userId/messageId/roomId as int are coerced, not '
        'dropped to empty', () {
      final starred = MessageMapper.starredFromJson({
        'userId': 1,
        'messageId': 2,
        'roomId': 3,
      });
      expect(starred.userId, '1');
      expect(starred.messageId, '2');
      expect(starred.roomId, '3');
    });

    test('reportFromJson tolerates garbage', () {
      final inputs = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'reportedAt': 'not-a-date'},
      ];
      for (final input in inputs) {
        expect(() => MessageMapper.reportFromJson(input), returnsNormally);
      }
    });

    test('reportFromJson reporterId/messageId/roomId as int are coerced, '
        'not dropped to empty', () {
      final report = MessageMapper.reportFromJson({
        'reporterId': 1,
        'messageId': 2,
        'roomId': 3,
      });
      expect(report.reporterId, '1');
      expect(report.messageId, '2');
      expect(report.roomId, '3');
    });

    test('reactionFromJson tolerates garbage', () {
      final inputs = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'emoji': null, 'count': null},
        {'emoji': '👍', 'count': 0, 'users': <dynamic>[]},
      ];
      for (final input in inputs) {
        expect(() => MessageMapper.reactionFromJson(input), returnsNormally);
      }
    });
  });

  group('MessageMapper fuzz — random property-based', () {
    final random = Random(4242);

    String randomString(int len) {
      const chars =
          'abcdefghijklmnopqrstuvwxyz0123456789-_:;"\'{}[]\u200B\u202E ';
      final buf = StringBuffer();
      for (var i = 0; i < len; i++) {
        buf.write(chars[random.nextInt(chars.length)]);
      }
      return buf.toString();
    }

    test('100 random schema-shaped inputs', () {
      for (var i = 0; i < 100; i++) {
        final json = <String, dynamic>{
          'id': random.nextBool() ? randomString(8) : null,
          'from': random.nextBool() ? randomString(8) : null,
          'timestamp': randomString(20),
          'text': random.nextBool() ? randomString(random.nextInt(120)) : null,
          'messageType': random.nextBool()
              ? randomString(8)
              : ['regular', 'attachment', 'reaction', 'reply', 'audio'][random
                    .nextInt(5)],
          'attachmentUrl': random.nextBool() ? randomString(40) : null,
          'referencedMessageId': random.nextBool() ? randomString(6) : null,
          'reaction': random.nextBool() ? randomString(2) : null,
          'reply': random.nextBool() ? randomString(20) : null,
          'metadata': random.nextBool()
              ? <String, dynamic>{
                  'edited': random.nextBool(),
                  'forwarded': random.nextBool(),
                  'system': random.nextBool(),
                }
              : null,
          'receipt': [
            'sent',
            'delivered',
            'read',
            'unknown',
            null,
          ][random.nextInt(5)],
          'isDeleted': random.nextBool(),
        };
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });
  });
}
