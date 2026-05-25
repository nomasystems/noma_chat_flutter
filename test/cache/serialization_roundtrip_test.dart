import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
// Serialization helpers live in the cache layer (not re-exported).
import 'package:noma_chat/src/cache/serialization.dart';

/// Round-trip coverage for the cache serialization helpers — reactions,
/// pins, receipts (otherwise untested) plus message/room with the optional
/// fields populated so the conditional `if (x != null)` map entries run.
void main() {
  group('serialization — reactions / pins / receipts', () {
    test('AggregatedReaction round-trips', () {
      const r = AggregatedReaction(emoji: '👍', count: 3, users: ['a', 'b']);
      final back = reactionFromMap(reactionToMap(r));
      expect(back.emoji, '👍');
      expect(back.count, 3);
      expect(back.users, ['a', 'b']);
    });

    test('MessagePin round-trips', () {
      final pin = MessagePin(
        roomId: 'r1',
        messageId: 'm1',
        pinnedBy: 'u1',
        pinnedAt: DateTime(2026, 1, 2, 3, 4, 5),
      );
      final back = pinFromMap(pinToMap(pin));
      expect(back.roomId, 'r1');
      expect(back.messageId, 'm1');
      expect(back.pinnedBy, 'u1');
      expect(back.pinnedAt, DateTime(2026, 1, 2, 3, 4, 5));
    });

    test('ReadReceipt round-trips with and without optional fields', () {
      final full = ReadReceipt(
        userId: 'u1',
        lastReadMessageId: 'm9',
        lastReadAt: DateTime(2026, 5, 1),
      );
      final back = receiptFromMap(receiptToMap(full));
      expect(back.userId, 'u1');
      expect(back.lastReadMessageId, 'm9');
      expect(back.lastReadAt, DateTime(2026, 5, 1));

      const minimal = ReadReceipt(userId: 'u2');
      final backMin = receiptFromMap(receiptToMap(minimal));
      expect(backMin.userId, 'u2');
      expect(backMin.lastReadMessageId, isNull);
      expect(backMin.lastReadAt, isNull);
    });
  });

  group('serialization — message with optional fields', () {
    test('messageToMap/messageFromMap round-trips populated fields', () {
      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'hello',
        attachmentUrl: 'https://x/file.png',
        referencedMessageId: 'm0',
        reaction: '👍',
        metadata: const {'k': 'v'},
        receipt: ReceiptStatus.read,
        isEdited: true,
        isDeleted: true,
        isForwarded: true,
        isSystem: true,
        mimeType: 'image/png',
        fileName: 'file.png',
        fileSize: '1234',
        thumbnailUrl: 'https://x/thumb.png',
      );

      final map = messageToMap(msg);
      // Conditional entries are present.
      expect(map['text'], 'hello');
      expect(map['attachmentUrl'], 'https://x/file.png');
      expect(map['referencedMessageId'], 'm0');
      expect(map['isEdited'], true);
      expect(map['mimeType'], 'image/png');
      expect(map['fileSize'], '1234');

      final back = messageFromMap(map);
      expect(back.id, 'm1');
      expect(back.text, 'hello');
      expect(back.receipt, ReceiptStatus.read);
      expect(back.isDeleted, true);
      expect(back.fileName, 'file.png');
    });
  });

  group('serialization — room with optional fields', () {
    test('roomToMap/roomFromMap round-trips populated fields', () {
      const room = ChatRoom(
        id: 'r1',
        owner: 'u1',
        name: 'Room',
        subject: 'Subject',
        avatarUrl: 'https://x/a.png',
        custom: {'flag': true},
      );

      final map = roomToMap(room);
      expect(map['owner'], 'u1');
      expect(map['name'], 'Room');
      expect(map['subject'], 'Subject');
      expect(map['avatarUrl'], 'https://x/a.png');

      final back = roomFromMap(map);
      expect(back.id, 'r1');
      expect(back.name, 'Room');
      expect(back.owner, 'u1');
    });
  });
}
