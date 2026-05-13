import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageMapper', () {
    test('fromJson maps all fields', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-12-25T20:00:00Z',
        'text': 'Hello',
        'messageType': 'regular',
        'attachmentUrl': 'https://example.com/file.png',
        'referencedMessageId': 'msg-0',
        'reaction': '👍',
        'reply': 'Re: Hello',
        'metadata': {'key': 'val'},
        'receipt': 'read',
      });
      expect(msg.id, 'msg-1');
      expect(msg.from, 'user-1');
      expect(msg.text, 'Hello');
      expect(msg.messageType, MessageType.regular);
      expect(msg.attachmentUrl, 'https://example.com/file.png');
      expect(msg.referencedMessageId, 'msg-0');
      expect(msg.reaction, '👍');
      expect(msg.reply, 'Re: Hello');
      expect(msg.receipt, ReceiptStatus.read);
    });

    test('parseMessageType handles all types including forward', () {
      for (final type in ['regular', 'attachment', 'reaction', 'reply', 'audio', 'forward']) {
        final msg = MessageMapper.fromJson({
          'id': 'msg-1',
          'from': 'u-1',
          'timestamp': '2024-01-01T00:00:00Z',
          'messageType': type,
        });
        expect(msg.messageType.name, type);
      }
    });

    test('forward message exposes ForwardInfo via getter', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'u-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'forward',
        'metadata': {
          'forwardedFrom': 'user-2',
          'forwardedFromRoom': 'room-orig',
          'forwardedMessageId': 'msg-orig',
        },
      });
      expect(msg.forwardInfo, isNotNull);
      expect(msg.forwardInfo!.forwardedFrom, 'user-2');
      expect(msg.forwardInfo!.forwardedFromRoom, 'room-orig');
      expect(msg.forwardInfo!.forwardedMessageId, 'msg-orig');
    });

    test('non-forward message has null ForwardInfo', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'u-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'regular',
      });
      expect(msg.forwardInfo, isNull);
    });

    test('forward messageType is parsed correctly', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'u-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'forward',
        'metadata': {
          'forwardedFrom': 'user-2',
          'forwardedFromRoom': 'room-orig',
          'forwardedMessageId': 'msg-orig',
        },
      });
      expect(msg.messageType, MessageType.forward);
      expect(msg.metadata?['forwardedFrom'], 'user-2');
    });

    test('unknown messageType defaults to regular', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'u-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'unknown',
      });
      expect(msg.messageType, MessageType.regular);
    });

    test('unknown messageType logs warning', () {
      final warnings = <String>[];
      MessageMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => MessageMapper.logger = null);

      MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'u-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'future_type',
      });
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('unknown messageType'));
    });

    test('known messageTypes do not log warning', () {
      final warnings = <String>[];
      MessageMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => MessageMapper.logger = null);

      for (final type in ['regular', 'attachment', 'reaction', 'reply', 'audio', 'forward']) {
        MessageMapper.fromJson({
          'id': 'msg-1',
          'from': 'u-1',
          'timestamp': '2024-01-01T00:00:00Z',
          'messageType': type,
        });
      }
      expect(warnings, isEmpty);
    });

    test('readReceiptFromJson maps fields', () {
      final receipt = MessageMapper.readReceiptFromJson({
        'userId': 'u-1',
        'lastReadMessageId': 'msg-5',
        'lastReadAt': '2024-12-25T20:00:00Z',
      });
      expect(receipt.userId, 'u-1');
      expect(receipt.lastReadMessageId, 'msg-5');
      expect(receipt.lastReadAt, isNotNull);
    });

    test('scheduledFromJson maps fields', () {
      final scheduled = MessageMapper.scheduledFromJson({
        'id': 'sch-1',
        'userId': 'u-1',
        'roomId': 'r-1',
        'sendAt': '2024-12-25T20:00:00Z',
        'createdAt': '2024-12-20T10:00:00Z',
        'text': 'Scheduled msg',
      });
      expect(scheduled.id, 'sch-1');
      expect(scheduled.text, 'Scheduled msg');
    });

    test('pinFromJson maps fields', () {
      final pin = MessageMapper.pinFromJson({
        'roomId': 'r-1',
        'messageId': 'msg-1',
        'pinnedBy': 'u-1',
        'pinnedAt': '2024-12-25T20:00:00Z',
      });
      expect(pin.roomId, 'r-1');
      expect(pin.pinnedBy, 'u-1');
    });

    test('reactionFromJson maps fields', () {
      final reaction = MessageMapper.reactionFromJson({
        'emoji': '❤️',
        'count': 3,
        'users': ['u-1', 'u-2', 'u-3'],
      });
      expect(reaction.emoji, '❤️');
      expect(reaction.count, 3);
      expect(reaction.users.length, 3);
    });

    test('fromJson with empty id/from logs warning', () {
      final warnings = <String>[];
      MessageMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => MessageMapper.logger = null);

      MessageMapper.fromJson({
        'timestamp': '2024-01-01T00:00:00Z',
      });
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('empty id'));
    });

    test('fromJson with valid id/from does not log warning', () {
      final warnings = <String>[];
      MessageMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => MessageMapper.logger = null);

      MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
      });
      expect(warnings, isEmpty);
    });

    test('infers reply type when referencedMessageId present without explicit messageType', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': 'Great idea!',
        'referencedMessageId': 'msg-0',
      });
      expect(msg.messageType, MessageType.reply);
      expect(msg.referencedMessageId, 'msg-0');
    });

    test('infers reply type when referencedMessageId present with regular messageType', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'text': 'Great idea!',
        'messageType': 'regular',
        'referencedMessageId': 'msg-0',
      });
      expect(msg.messageType, MessageType.reply);
    });

    test('does not infer reply type when reaction is present', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'referencedMessageId': 'msg-0',
        'reaction': '👍',
      });
      expect(msg.messageType, MessageType.regular);
    });

    test('preserves explicit reply messageType', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'messageType': 'reply',
        'referencedMessageId': 'msg-0',
      });
      expect(msg.messageType, MessageType.reply);
    });

    test('infers location type when metadata has numeric lat and lng', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {'lat': 40.41, 'lng': -3.70},
      });
      expect(msg.messageType, MessageType.location);
      expect(msg.metadata?['lat'], 40.41);
      expect(msg.metadata?['lng'], -3.70);
    });

    test('infers location type when metadata arrives as JSON string', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': '{"lat":40.41,"lng":-3.70,"staticMapUrl":"https://x"}',
      });
      expect(msg.messageType, MessageType.location);
      expect(msg.metadata?['staticMapUrl'], 'https://x');
    });

    test('does not infer location when lat or lng are missing', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {'lat': 40.41},
      });
      expect(msg.messageType, MessageType.regular);
    });

    test('attachment metadata takes precedence over location inference', () {
      final msg = MessageMapper.fromJson({
        'id': 'msg-1',
        'from': 'user-1',
        'timestamp': '2024-01-01T00:00:00Z',
        'metadata': {
          'attachmentUrl': 'https://x/file.png',
          'mimeType': 'image/png',
          'lat': 40.41,
          'lng': -3.70,
        },
      });
      expect(msg.messageType, MessageType.attachment);
    });
  });
}
