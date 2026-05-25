import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/dto/message_dto.dart';

void main() {
  group('MessageDto', () {
    group('fromJson', () {
      test('deserializes all fields from standard keys', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'text': 'Hello world',
          'messageType': 'regular',
          'attachmentUrl': 'https://example.com/file.pdf',
          'referencedMessageId': 'ref-msg-1',
          'reaction': '👍',
          'reply': 'reply text',
          'metadata': {'key': 'value'},
          'isDeleted': false,
          'receipt': 'read',
          'sourceRoomId': 'source-room-1',
        });

        expect(dto.id, 'msg-1');
        expect(dto.from, 'user-1');
        expect(dto.timestamp, '2026-01-01T00:00:00Z');
        expect(dto.text, 'Hello world');
        expect(dto.messageType, 'regular');
        expect(dto.attachmentUrl, 'https://example.com/file.pdf');
        expect(dto.referencedMessageId, 'ref-msg-1');
        expect(dto.reaction, '👍');
        expect(dto.reply, 'reply text');
        expect(dto.metadata, {'key': 'value'});
        expect(dto.isDeleted, isFalse);
        expect(dto.receipt, 'read');
        expect(dto.sourceRoomId, 'source-room-1');
      });

      test('uses messageId as fallback when id is absent', () {
        final dto = MessageDto.fromJson({
          'messageId': 'msg-alt',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(dto.id, 'msg-alt');
      });

      test('prefers id over messageId when both present', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-primary',
          'messageId': 'msg-secondary',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(dto.id, 'msg-primary');
      });

      test('returns empty string for null id and from', () {
        final dto = MessageDto.fromJson({'timestamp': '2026-01-01T00:00:00Z'});
        expect(dto.id, '');
        expect(dto.from, '');
      });

      test('converts non-string id to string via _strOf', () {
        final dto = MessageDto.fromJson({
          'id': 42,
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(dto.id, '42');
      });

      test('returns null for non-string optional text fields', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'text': 123,
          'messageType': true,
          'attachmentUrl': [],
          'referencedMessageId': {},
          'reaction': 0,
          'reply': false,
          'receipt': 1.5,
          'sourceRoomId': [],
        });

        expect(dto.text, isNull);
        expect(dto.messageType, isNull);
        expect(dto.attachmentUrl, isNull);
        expect(dto.referencedMessageId, isNull);
        expect(dto.reaction, isNull);
        expect(dto.reply, isNull);
        expect(dto.receipt, isNull);
        expect(dto.sourceRoomId, isNull);
      });

      test('parses metadata from JSON-encoded string', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'metadata': '{"linkUrl":"https://example.com","linkTitle":"Example"}',
        });
        expect(dto.metadata, {
          'linkUrl': 'https://example.com',
          'linkTitle': 'Example',
        });
      });

      test('returns null for malformed JSON metadata string', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'metadata': '{not: valid json',
        });
        expect(dto.metadata, isNull);
      });

      test('returns null when metadata JSON string decodes to non-map', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'metadata': '[1, 2, 3]',
        });
        expect(dto.metadata, isNull);
      });

      test('returns null for empty string metadata', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'metadata': '',
        });
        expect(dto.metadata, isNull);
      });

      test('isDeleted defaults to false when absent', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(dto.isDeleted, isFalse);
      });

      test('isDeleted is true when json value is true', () {
        final dto = MessageDto.fromJson({
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2026-01-01T00:00:00Z',
          'isDeleted': true,
        });
        expect(dto.isDeleted, isTrue);
      });
    });

    group('toSendJson', () {
      test('includes only non-null fields with default messageType', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
          text: 'Hello',
        );
        final json = dto.toSendJson();

        expect(json['text'], 'Hello');
        expect(json['messageType'], 'regular');
        expect(json.containsKey('referencedMessageId'), isFalse);
        expect(json.containsKey('reaction'), isFalse);
        expect(json.containsKey('attachmentUrl'), isFalse);
        expect(json.containsKey('sourceRoomId'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
      });

      test('omits text key when text is null', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
        );
        expect(dto.toSendJson().containsKey('text'), isFalse);
      });

      test('includes all optional fields when set', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
          text: 'Hello',
          messageType: 'audio',
          referencedMessageId: 'ref-1',
          reaction: '👍',
          attachmentUrl: 'https://example.com/audio.m4a',
          sourceRoomId: 'source-room',
          metadata: {'duration': 42},
        );
        final json = dto.toSendJson();

        expect(json['text'], 'Hello');
        expect(json['messageType'], 'audio');
        expect(json['referencedMessageId'], 'ref-1');
        expect(json['reaction'], '👍');
        expect(json['attachmentUrl'], 'https://example.com/audio.m4a');
        expect(json['sourceRoomId'], 'source-room');
        expect(json['metadata'], {'duration': 42});
      });

      test('does not include id, from, timestamp, reply or receipt', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
          reply: 'some reply',
          receipt: 'read',
        );
        final json = dto.toSendJson();

        expect(json.containsKey('id'), isFalse);
        expect(json.containsKey('from'), isFalse);
        expect(json.containsKey('timestamp'), isFalse);
        expect(json.containsKey('reply'), isFalse);
        expect(json.containsKey('receipt'), isFalse);
      });

      test('defaults messageType to "regular" when null', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
        );
        expect(dto.toSendJson()['messageType'], 'regular');
      });
    });

    group('toJson', () {
      test('always includes id, from, timestamp and messageType', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
        );
        final json = dto.toJson();

        expect(json['id'], 'msg-1');
        expect(json['from'], 'user-1');
        expect(json['timestamp'], '2026-01-01T00:00:00Z');
        expect(json['messageType'], 'regular');
      });

      test('includes reply field (unlike toSendJson)', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
          reply: 'forwarded text',
        );

        expect(dto.toSendJson().containsKey('reply'), isFalse);
        expect(dto.toJson()['reply'], 'forwarded text');
      });

      test('includes receipt field', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
          receipt: 'delivered',
        );
        expect(dto.toJson()['receipt'], 'delivered');
      });

      test('serializes all optional fields when set', () {
        const dto = MessageDto(
          id: 'msg-2',
          from: 'user-2',
          timestamp: '2026-01-02T00:00:00Z',
          text: 'Full message',
          messageType: 'audio',
          attachmentUrl: 'https://example.com/a.m4a',
          referencedMessageId: 'ref-42',
          reaction: '❤️',
          reply: 'reply text',
          metadata: {'duration': 120},
          receipt: 'read',
        );
        final json = dto.toJson();

        expect(json['text'], 'Full message');
        expect(json['messageType'], 'audio');
        expect(json['attachmentUrl'], 'https://example.com/a.m4a');
        expect(json['referencedMessageId'], 'ref-42');
        expect(json['reaction'], '❤️');
        expect(json['reply'], 'reply text');
        expect(json['metadata'], {'duration': 120});
        expect(json['receipt'], 'read');
      });

      test('omits absent optional keys rather than including nulls', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
        );
        final json = dto.toJson();

        expect(json.containsKey('text'), isFalse);
        expect(json.containsKey('attachmentUrl'), isFalse);
        expect(json.containsKey('referencedMessageId'), isFalse);
        expect(json.containsKey('reaction'), isFalse);
        expect(json.containsKey('reply'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
        expect(json.containsKey('receipt'), isFalse);
      });

      test('defaults messageType to "regular" when null', () {
        const dto = MessageDto(
          id: 'msg-1',
          from: 'user-1',
          timestamp: '2026-01-01T00:00:00Z',
        );
        expect(dto.toJson()['messageType'], 'regular');
      });
    });
  });
}
