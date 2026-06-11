import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/dto/message_dto.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/src/mock/mock_chat_client.dart';

void main() {
  group('clientMessageId — wire contract', () {
    test('MessageDto reads the echo from metadata.clientMessageId', () {
      // The backend round-trips the key INSIDE metadata, not top-level.
      final dto = MessageDto.fromJson({
        'id': 'm1',
        'from': 'u1',
        'timestamp': '2026-06-15T10:00:00Z',
        'text': 'hi',
        'messageType': 'regular',
        'metadata': {'clientMessageId': 'cmid-1'},
      });
      expect(dto.clientMessageId, 'cmid-1');
      // The send representation still emits it top-level (NewMessage field).
      expect(dto.toSendJson()['clientMessageId'], 'cmid-1');
    });

    test(
      'MessageDto ignores a top-level clientMessageId (echo is metadata)',
      () {
        final dto = MessageDto.fromJson({
          'id': 'm1',
          'from': 'u1',
          'timestamp': '2026-06-15T10:00:00Z',
          'clientMessageId': 'wrong-place',
        });
        expect(dto.clientMessageId, isNull);
      },
    );

    test('MessageDto omits clientMessageId when absent', () {
      final dto = MessageDto.fromJson({
        'id': 'm1',
        'from': 'u1',
        'timestamp': '2026-06-15T10:00:00Z',
      });
      expect(dto.clientMessageId, isNull);
      expect(dto.toSendJson().containsKey('clientMessageId'), isFalse);
    });

    test('MessageMapper lifts the metadata echo onto ChatMessage and strips it '
        'from the public metadata', () {
      final msg = MessageMapper.fromJson({
        'id': 'server-id',
        'from': 'u1',
        'timestamp': '2026-06-15T10:00:00Z',
        'text': 'hi',
        'metadata': {'clientMessageId': '_pending_42', 'foo': 'bar'},
      });
      expect(msg.id, 'server-id');
      expect(msg.clientMessageId, '_pending_42');
      // The idempotency key is not leaked into the public metadata map.
      expect(msg.metadata?.containsKey('clientMessageId') ?? false, isFalse);
      expect(msg.metadata?['foo'], 'bar');
    });

    test('MessageMapper leaves clientMessageId null when not echoed', () {
      final msg = MessageMapper.fromJson({
        'id': 'server-id',
        'from': 'u1',
        'timestamp': '2026-06-15T10:00:00Z',
        'text': 'hi',
      });
      expect(msg.clientMessageId, isNull);
    });
  });

  group('clientMessageId — offline queue idempotency', () {
    PendingSendMessage build() => PendingSendMessage(
      id: 'p1',
      roomId: 'r1',
      text: 'hi',
      tempId: '_pending_7',
      clientMessageId: '_pending_7',
    );

    test('PendingSendMessage serializes the idempotency key', () {
      expect(build().toJson()['clientMessageId'], '_pending_7');
    });

    test('withRetry preserves the same key across retries', () {
      final retried = build().withRetry(attempts: 3);
      expect(retried.clientMessageId, '_pending_7');
      expect(retried.attempts, 3);
    });
  });

  group('clientMessageId — mock echo', () {
    test('MockChatClient.send echoes the supplied key back', () async {
      final client = MockChatClient(currentUserId: 'me');
      final result = await client.messages.send(
        'r1',
        text: 'hi',
        clientMessageId: 'cmid-9',
      );
      expect(result.dataOrNull?.clientMessageId, 'cmid-9');
    });
  });
}
