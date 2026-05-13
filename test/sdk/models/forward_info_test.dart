import 'package:noma_chat/noma_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForwardInfo.tryFromMetadata', () {
    test('returns ForwardInfo when all metadata keys present', () {
      final info = ForwardInfo.tryFromMetadata({
        'forwardedFrom': 'user1',
        'forwardedFromRoom': 'room1',
        'forwardedMessageId': 'msg1',
      });
      expect(info, isNotNull);
      expect(info!.forwardedFrom, 'user1');
      expect(info.forwardedFromRoom, 'room1');
      expect(info.forwardedMessageId, 'msg1');
    });

    test('returns null when metadata is null', () {
      expect(ForwardInfo.tryFromMetadata(null), isNull);
    });

    test('returns null when forwardedFrom key is missing', () {
      expect(
        ForwardInfo.tryFromMetadata({'other': 'data'}),
        isNull,
      );
    });
  });

  group('ForwardInfo.tryFromMessage', () {
    test('prefers metadata when available', () {
      final info = ForwardInfo.tryFromMessage(
        from: 'sender',
        referencedMessageId: 'ref1',
        metadata: {
          'forwardedFrom': 'original-sender',
          'forwardedFromRoom': 'original-room',
          'forwardedMessageId': 'original-msg',
        },
      );
      expect(info!.forwardedFrom, 'original-sender');
      expect(info.forwardedFromRoom, 'original-room');
      expect(info.forwardedMessageId, 'original-msg');
    });

    test('falls back to message fields when metadata is empty', () {
      final info = ForwardInfo.tryFromMessage(
        from: 'sender',
        referencedMessageId: 'ref1',
        metadata: {'sourceRoomId': 'source-room'},
      );
      expect(info!.forwardedFrom, 'sender');
      expect(info.forwardedFromRoom, 'source-room');
      expect(info.forwardedMessageId, 'ref1');
    });

    test('falls back with null metadata', () {
      final info = ForwardInfo.tryFromMessage(
        from: 'sender',
        referencedMessageId: 'ref1',
      );
      expect(info!.forwardedFrom, 'sender');
      expect(info.forwardedFromRoom, '');
      expect(info.forwardedMessageId, 'ref1');
    });

    test('returns null when from is null', () {
      final info = ForwardInfo.tryFromMessage(
        from: null,
        referencedMessageId: 'ref1',
      );
      expect(info, isNull);
    });
  });

  group('ChatMessage.forwardInfo', () {
    test('returns null for non-forward messages', () {
      final msg = ChatMessage(
        id: 'msg1',
        from: 'user1',
        timestamp: DateTime(2026, 1, 1),
        text: 'hello',
      );
      expect(msg.forwardInfo, isNull);
    });

    test('returns ForwardInfo for forward messages without metadata', () {
      final msg = ChatMessage(
        id: 'msg1',
        from: 'user1',
        timestamp: DateTime(2026, 1, 1),
        messageType: MessageType.forward,
        referencedMessageId: 'orig-msg',
        metadata: {'sourceRoomId': 'orig-room'},
      );
      final info = msg.forwardInfo;
      expect(info, isNotNull);
      expect(info!.forwardedFrom, 'user1');
      expect(info.forwardedFromRoom, 'orig-room');
      expect(info.forwardedMessageId, 'orig-msg');
    });

    test('returns ForwardInfo from full metadata', () {
      final msg = ChatMessage(
        id: 'msg1',
        from: 'user1',
        timestamp: DateTime(2026, 1, 1),
        messageType: MessageType.forward,
        metadata: {
          'forwardedFrom': 'orig-user',
          'forwardedFromRoom': 'orig-room',
          'forwardedMessageId': 'orig-msg',
        },
      );
      final info = msg.forwardInfo;
      expect(info, isNotNull);
      expect(info!.forwardedFrom, 'orig-user');
    });
  });
}
