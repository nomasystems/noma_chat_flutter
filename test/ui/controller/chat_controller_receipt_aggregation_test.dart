import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// per-user receipt aggregation in [ChatController].
///
/// Asserts the WhatsApp-style semantics the controller is supposed to
/// enforce:
///
/// * 1:1 DM: any peer ack flips the aggregated status. One `read` from
///   the only other member is enough to render ✓✓-blue.
/// * Group: the bubble only flips to ✓✓-blue once *every* non-sender
///   member has acked `read`. Partial reads stay at `delivered` (or
///   `sent` if no one even delivered yet).
/// * High-water-mark propagation: when a recipient reads message N,
///   every older message from the same sender is implicitly read too —
///   but only by that recipient, and only for the same sender. Older
///   messages by a different sender stay untouched.
/// * [ChatController.clearMessages] resets both the per-user tracking
///   and the aggregated cache so a re-loaded room doesn't carry over
///   stale acks.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final t0 = DateTime.utc(2026, 1, 1, 10, 0, 0);

  ChatMessage own(String id, {Duration offset = Duration.zero}) =>
      ChatMessage(id: id, from: 'me', timestamp: t0.add(offset), text: id);

  group('DM aggregation (single other user)', () {
    test('any delivered → aggregated = delivered', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('any read → aggregated = read', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('no receipts → aggregated absent (falls back to sent)', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      expect(c.receiptStatuses['m1'], isNull);
    });
  });

  group('Group aggregation (multiple other users)', () {
    ChatController buildGroup() => ChatController(
      initialMessages: [own('m1')],
      currentUser: me,
      otherUsers: const [
        ChatUser(id: 'u1', displayName: 'Alice'),
        ChatUser(id: 'u2', displayName: 'Bob'),
        ChatUser(id: 'u3', displayName: 'Charlie'),
      ],
    );

    test('only one read → aggregated stays at sent (no blue)', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      // Two members still haven't ack'd → not delivered-by-all either.
      expect(c.receiptStatuses['m1'], ReceiptStatus.sent);
    });

    test('all delivered, none read → aggregated = delivered', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u3');
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('two read + one delivered → aggregated = delivered', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u3');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
      // u3 only acknowledged delivery, not read → bubble must NOT flip
      // to blue yet.
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('all read → aggregated = read (blue)', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u3');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });
  });

  group('High-water-mark propagation', () {
    test('reading the latest msg from a sender flips all older ones for '
        'that sender, but never crosses to a different sender', () {
      final c = ChatController(
        initialMessages: [
          own('m1', offset: const Duration(seconds: 1)),
          own('m2', offset: const Duration(seconds: 2)),
          // A foreign message in the middle — should NOT inherit u1's read.
          ChatMessage(
            id: 'm-foreign',
            from: 'u3',
            timestamp: t0.add(const Duration(seconds: 3)),
            text: 'foreign',
          ),
          own('m3', offset: const Duration(seconds: 4)),
        ],
        currentUser: me,
        otherUsers: const [
          ChatUser(id: 'u1', displayName: 'Alice'),
          ChatUser(id: 'u2', displayName: 'Bob'),
        ],
      );
      addTearDown(c.dispose);

      // u1 reads the latest own message. u2 hasn't acked yet → still
      // "sent" in a 2-other-user group.
      c.updateReceipt('m3', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m3'], ReceiptStatus.sent);

      // Now u2 reads m3 → all otherUsers have read → m3 flips to read.
      c.updateReceipt('m3', ReceiptStatus.read, fromUserId: 'u2');
      expect(c.receiptStatuses['m3'], ReceiptStatus.read);
      // Propagation: m1 and m2 (older, same sender) inherit "read by
      // u1 and u2" too → also flip to read.
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
      expect(c.receiptStatuses['m2'], ReceiptStatus.read);
      // The foreign message has a different sender → untouched.
      expect(c.receiptStatuses['m-foreign'], isNull);
    });
  });

  group('clearMessages resets all per-user tracking', () {
    test('aggregated and per-user maps are wiped after clearMessages', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.clearMessages();
      expect(c.receiptStatuses, isEmpty);
      // After re-seeding the same id, status starts from scratch.
      c.addMessage(own('m1'));
      expect(c.receiptStatuses['m1'], isNull);
    });
  });
}
