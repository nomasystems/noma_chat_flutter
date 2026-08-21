import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Where the "N new messages" line lands: on the first message after the
/// local user's own read cursor, never on a position counted back from the
/// end of the list, and never on one of the user's own messages.
void main() {
  const me = 'me';

  ChatMessage msg(String id, String from, int minute) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1, 10, minute),
    text: id,
  );

  // Three incoming messages the user answered at the end. The room badge
  // says 3 unread, which is one more than the cursor accounts for — a
  // stale badge is the normal case, not an edge one.
  final history = [
    msg('m1', 'u1', 1),
    msg('m2', 'u1', 2),
    msg('m3', 'u1', 3),
    msg('mine', me, 4),
  ];

  group('anchored on the read cursor', () {
    test('lands on the first message after lastReadMessageId, not on the '
        'position the badge count points at', () {
      final boundary = resolveUnreadBoundary(
        messages: history,
        currentUserId: me,
        fallbackUnreadCount: 3,
        ownReadCursor: const ReadReceipt(userId: me, lastReadMessageId: 'm2'),
      );

      expect(boundary?.messageId, 'm3');
      expect(boundary?.count, 1);
    });

    test('falls back to lastReadAt when the cursor row is not loaded', () {
      final boundary = resolveUnreadBoundary(
        messages: history,
        currentUserId: me,
        fallbackUnreadCount: 3,
        ownReadCursor: ReadReceipt(
          userId: me,
          lastReadMessageId: 'evicted',
          lastReadAt: DateTime(2026, 1, 1, 10, 2),
        ),
      );

      expect(boundary?.messageId, 'm3');
      expect(boundary?.count, 1);
    });

    test('a cursor covering everything loaded degrades to the count instead of '
        'swallowing the divider', () {
      final boundary = resolveUnreadBoundary(
        messages: history,
        currentUserId: me,
        fallbackUnreadCount: 1,
        ownReadCursor: const ReadReceipt(userId: me, lastReadMessageId: 'm3'),
      );

      expect(boundary?.messageId, 'm3');
      expect(boundary?.count, 1);
    });
  });

  group('degrading without a cursor', () {
    test('counts back over incoming messages only, never over own ones', () {
      final boundary = resolveUnreadBoundary(
        messages: [msg('m1', 'u1', 1), msg('m2', 'u1', 2), msg('mine', me, 3)],
        currentUserId: me,
        fallbackUnreadCount: 2,
      );

      expect(boundary?.messageId, 'm1');
      expect(boundary?.count, 2);
    });

    test('an all-incoming history still counts back exactly as before', () {
      final boundary = resolveUnreadBoundary(
        messages: [msg('m1', 'u1', 1), msg('m2', 'u1', 2), msg('m3', 'u1', 3)],
        currentUserId: me,
        fallbackUnreadCount: 2,
      );

      expect(boundary?.messageId, 'm2');
      expect(boundary?.count, 2);
    });

    test('a room with nothing incoming has no boundary at all', () {
      final boundary = resolveUnreadBoundary(
        messages: [msg('mine', me, 1), msg('mine2', me, 2)],
        currentUserId: me,
        fallbackUnreadCount: 2,
      );

      expect(boundary, isNull);
    });

    test(
      'a count larger than the history clamps to the oldest incoming row',
      () {
        final boundary = resolveUnreadBoundary(
          messages: history,
          currentUserId: me,
          fallbackUnreadCount: 50,
        );

        expect(boundary?.messageId, 'm1');
        expect(boundary?.count, 3);
      },
    );
  });
}
